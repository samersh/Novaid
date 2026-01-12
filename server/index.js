const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST'],
  },
});

// In-memory storage for users and sessions
const users = new Map(); // Map<socketId, { id, code, role, isAvailable }>
const usersByCode = new Map(); // Map<code, socketId>
const usersById = new Map(); // Map<userId, socketId>
const sessions = new Map(); // Map<sessionId, { userId, professionalId, status }>
const availableProfessionals = new Set(); // Set of professional socket IDs

// Generate unique session ID
function generateSessionId() {
  return `session_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
}

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok', connections: users.size });
});

// Get available professionals count
app.get('/api/professionals/available', (req, res) => {
  res.json({ count: availableProfessionals.size });
});

// Socket.IO connection handling
io.on('connection', (socket) => {
  console.log(`Client connected: ${socket.id}`);
  const { userId, role } = socket.handshake.auth;

  // Register user
  socket.on('user:register', (data) => {
    const { userId: uid, role: userRole } = data;
    const userCode = generateUserCode();

    const userData = {
      id: uid,
      code: userCode,
      role: userRole,
      isAvailable: true,
      socketId: socket.id,
    };

    users.set(socket.id, userData);
    usersByCode.set(userCode, socket.id);
    usersById.set(uid, socket.id);

    if (userRole === 'professional') {
      availableProfessionals.add(socket.id);
    }

    socket.emit('user:registered', { uniqueCode: userCode });
    console.log(`User registered: ${uid} (${userRole}) with code ${userCode}`);
  });

  // Initiate call (from user)
  socket.on('call:initiate', (data) => {
    const { callerId, targetCode } = data;
    const caller = users.get(socket.id);

    if (!caller) {
      socket.emit('error', { message: 'User not registered' });
      return;
    }

    // Find an available professional
    let professionalSocketId = null;

    if (targetCode) {
      // Target specific professional by code
      professionalSocketId = usersByCode.get(targetCode);
    } else {
      // Find any available professional
      for (const profId of availableProfessionals) {
        const prof = users.get(profId);
        if (prof && prof.isAvailable) {
          professionalSocketId = profId;
          break;
        }
      }
    }

    if (!professionalSocketId) {
      socket.emit('call:rejected', { reason: 'No professionals available' });
      return;
    }

    const professional = users.get(professionalSocketId);

    // Notify professional of incoming call
    io.to(professionalSocketId).emit('call:incoming', {
      callerId: caller.id,
      callerCode: caller.code,
      callerSocketId: socket.id,
    });

    console.log(`Call initiated from ${caller.code} to professional ${professional.code}`);
  });

  // Accept call (from professional)
  socket.on('call:accept', (data) => {
    const { callerId, professionalId } = data;
    const professional = users.get(socket.id);
    const callerSocketId = usersById.get(callerId);

    if (!professional || !callerSocketId) {
      socket.emit('error', { message: 'Invalid call acceptance' });
      return;
    }

    // Create session
    const sessionId = generateSessionId();
    sessions.set(sessionId, {
      userId: callerId,
      professionalId: professional.id,
      status: 'active',
      startTime: Date.now(),
    });

    // Mark professional as unavailable
    professional.isAvailable = false;
    availableProfessionals.delete(socket.id);

    // Notify caller that call was accepted
    io.to(callerSocketId).emit('call:accepted', {
      sessionId,
      professionalId: professional.id,
      professionalSocketId: socket.id,
    });

    // Also notify professional
    socket.emit('call:accepted', {
      sessionId,
      userId: callerId,
      userSocketId: callerSocketId,
    });

    console.log(`Call accepted. Session: ${sessionId}`);
  });

  // Reject call (from professional)
  socket.on('call:reject', (data) => {
    const { callerId, reason } = data;
    const callerSocketId = usersById.get(callerId);

    if (callerSocketId) {
      io.to(callerSocketId).emit('call:rejected', { reason });
    }

    console.log(`Call rejected: ${reason}`);
  });

  // End call
  socket.on('call:end', (data) => {
    const { userId: uid } = data;
    const user = users.get(socket.id);

    if (!user) return;

    // Find and end the session
    for (const [sessionId, session] of sessions) {
      if (session.userId === uid || session.professionalId === uid) {
        session.status = 'ended';
        session.endTime = Date.now();

        // Notify both parties
        const userSocketId = usersById.get(session.userId);
        const profSocketId = usersById.get(session.professionalId);

        if (userSocketId) io.to(userSocketId).emit('call:ended');
        if (profSocketId) {
          io.to(profSocketId).emit('call:ended');
          // Mark professional as available again
          const prof = users.get(profSocketId);
          if (prof) {
            prof.isAvailable = true;
            availableProfessionals.add(profSocketId);
          }
        }

        sessions.delete(sessionId);
        console.log(`Call ended. Session: ${sessionId}`);
        break;
      }
    }
  });

  // WebRTC signaling - Offer
  socket.on('signal:offer', (data) => {
    const { offer, from, to } = data;
    const targetSocketId = usersById.get(to);

    if (targetSocketId) {
      io.to(targetSocketId).emit('signal:offer', { offer, from });
      console.log(`Offer relayed from ${from} to ${to}`);
    }
  });

  // WebRTC signaling - Answer
  socket.on('signal:answer', (data) => {
    const { answer, from, to } = data;
    const targetSocketId = usersById.get(to);

    if (targetSocketId) {
      io.to(targetSocketId).emit('signal:answer', { answer, from });
      console.log(`Answer relayed from ${from} to ${to}`);
    }
  });

  // WebRTC signaling - ICE Candidate
  socket.on('signal:ice', (data) => {
    const { candidate, from, to } = data;
    const targetSocketId = usersById.get(to);

    if (targetSocketId) {
      io.to(targetSocketId).emit('signal:ice', { candidate, from });
    }
  });

  // Location update
  socket.on('location:update', (data) => {
    const { userId: uid, location } = data;

    // Find the session and relay to the other party
    for (const [sessionId, session] of sessions) {
      if (session.status !== 'active') continue;

      let targetUserId = null;
      if (session.userId === uid) {
        targetUserId = session.professionalId;
      } else if (session.professionalId === uid) {
        targetUserId = session.userId;
      }

      if (targetUserId) {
        const targetSocketId = usersById.get(targetUserId);
        if (targetSocketId) {
          io.to(targetSocketId).emit('location:update', { location });
        }
        break;
      }
    }
  });

  // Annotation
  socket.on('annotation:add', (data) => {
    const { userId: uid, annotation } = data;

    // Find session and relay annotation
    for (const [sessionId, session] of sessions) {
      if (session.status !== 'active') continue;

      let targetUserId = null;
      if (session.userId === uid) {
        targetUserId = session.professionalId;
      } else if (session.professionalId === uid) {
        targetUserId = session.userId;
      }

      if (targetUserId) {
        const targetSocketId = usersById.get(targetUserId);
        if (targetSocketId) {
          io.to(targetSocketId).emit('annotation:received', { annotation });
        }
        break;
      }
    }
  });

  // Clear annotations
  socket.on('annotation:clear', (data) => {
    const { userId: uid } = data;

    for (const [sessionId, session] of sessions) {
      if (session.status !== 'active') continue;

      let targetUserId = null;
      if (session.userId === uid) {
        targetUserId = session.professionalId;
      } else if (session.professionalId === uid) {
        targetUserId = session.userId;
      }

      if (targetUserId) {
        const targetSocketId = usersById.get(targetUserId);
        if (targetSocketId) {
          io.to(targetSocketId).emit('annotation:clear');
        }
        break;
      }
    }
  });

  // Freeze frame
  socket.on('frame:freeze', (data) => {
    const { userId: uid, frameData, timestamp } = data;

    for (const [sessionId, session] of sessions) {
      if (session.status !== 'active') continue;

      if (session.professionalId === uid) {
        const userSocketId = usersById.get(session.userId);
        if (userSocketId) {
          io.to(userSocketId).emit('frame:frozen', { frameData, timestamp });
        }
        break;
      }
    }
  });

  // Resume frame
  socket.on('frame:resume', (data) => {
    const { userId: uid } = data;

    for (const [sessionId, session] of sessions) {
      if (session.status !== 'active') continue;

      if (session.professionalId === uid) {
        const userSocketId = usersById.get(session.userId);
        if (userSocketId) {
          io.to(userSocketId).emit('frame:resumed');
        }
        break;
      }
    }
  });

  // Handle disconnect
  socket.on('disconnect', () => {
    const user = users.get(socket.id);

    if (user) {
      console.log(`Client disconnected: ${user.id} (${user.role})`);

      // Clean up
      usersByCode.delete(user.code);
      usersById.delete(user.id);
      availableProfessionals.delete(socket.id);

      // End any active sessions
      for (const [sessionId, session] of sessions) {
        if (session.userId === user.id || session.professionalId === user.id) {
          session.status = 'ended';

          const otherUserId = session.userId === user.id ? session.professionalId : session.userId;
          const otherSocketId = usersById.get(otherUserId);

          if (otherSocketId) {
            io.to(otherSocketId).emit('call:ended');
          }

          sessions.delete(sessionId);
        }
      }
    }

    users.delete(socket.id);
  });
});

// Generate a unique user code
function generateUserCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
}

// Start server
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`Signaling server running on port ${PORT}`);
});

module.exports = { app, server, io };
