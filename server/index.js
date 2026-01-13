/**
 * Novaid Signaling Server
 *
 * WebRTC signaling server for establishing peer-to-peer connections
 * between users and professionals for remote assistance.
 */

const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');

const app = express();
const server = http.createServer(app);

// Configure CORS
app.use(cors());

// Socket.IO configuration
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST'],
  },
  transports: ['websocket', 'polling'],
});

// Data stores
const connectedUsers = new Map(); // userId -> socketId
const connectedProfessionals = new Map(); // professionalId -> socketId
const activeCalls = new Map(); // callId -> { userId, professionalId, status }
const waitingUsers = []; // Queue of users waiting for a professional

// Utility functions
function getSocketById(socketId) {
  return io.sockets.sockets.get(socketId);
}

function findAvailableProfessional() {
  // Find a professional who is not in an active call
  for (const [professionalId, socketId] of connectedProfessionals) {
    const isInCall = Array.from(activeCalls.values()).some(
      (call) => call.professionalId === professionalId && call.status === 'active'
    );
    if (!isInCall) {
      return { professionalId, socketId };
    }
  }
  return null;
}

// Express routes
app.get('/', (req, res) => {
  res.json({
    status: 'running',
    service: 'Novaid Signaling Server',
    version: '1.0.0',
    connections: {
      users: connectedUsers.size,
      professionals: connectedProfessionals.size,
      activeCalls: activeCalls.size,
    },
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

// Socket.IO event handlers
io.on('connection', (socket) => {
  const userId = socket.handshake.query.userId;
  console.log(`Client connected: ${socket.id} (userId: ${userId})`);

  // Store socket mapping
  if (userId) {
    connectedUsers.set(userId, socket.id);
  }

  // Register as professional
  socket.on('register-professional', (data) => {
    const { userId: professionalId } = data;
    connectedProfessionals.set(professionalId, socket.id);
    console.log(`Professional registered: ${professionalId}`);

    // Notify any waiting users
    processWaitingUsers();
  });

  // User requests a call
  socket.on('request-call', (data) => {
    const { userId: callerId } = data;
    console.log(`Call requested by user: ${callerId}`);

    const available = findAvailableProfessional();

    if (available) {
      const { professionalId, socketId: professionalSocketId } = available;

      // Create call session
      const callId = uuidv4();
      activeCalls.set(callId, {
        userId: callerId,
        professionalId,
        status: 'pending',
        createdAt: Date.now(),
      });

      // Notify professional of incoming call
      const professionalSocket = getSocketById(professionalSocketId);
      if (professionalSocket) {
        professionalSocket.emit('call-request', {
          type: 'call-request',
          from: callerId,
          to: professionalId,
          callId,
          timestamp: Date.now(),
        });
      }

      // Notify user that call is being connected
      socket.emit('professional-available', {
        professionalId,
        callId,
      });
    } else {
      // Add to waiting queue
      if (!waitingUsers.includes(callerId)) {
        waitingUsers.push(callerId);
      }
      socket.emit('no-professional-available');
    }
  });

  // Professional accepts call
  socket.on('accept-call', (data) => {
    const { userId: professionalId, callerId } = data;
    console.log(`Call accepted: ${professionalId} -> ${callerId}`);

    // Find and update call
    for (const [callId, call] of activeCalls) {
      if (call.userId === callerId && call.professionalId === professionalId) {
        call.status = 'active';

        // Notify user
        const userSocketId = connectedUsers.get(callerId);
        const userSocket = getSocketById(userSocketId);
        if (userSocket) {
          userSocket.emit('call-accepted', {
            type: 'call-accepted',
            from: professionalId,
            to: callerId,
            callId,
            timestamp: Date.now(),
          });
        }
        break;
      }
    }
  });

  // Professional rejects call
  socket.on('reject-call', (data) => {
    const { userId: professionalId, callerId } = data;
    console.log(`Call rejected: ${professionalId} -> ${callerId}`);

    // Remove call from active calls
    for (const [callId, call] of activeCalls) {
      if (call.userId === callerId && call.professionalId === professionalId) {
        activeCalls.delete(callId);
        break;
      }
    }

    // Notify user
    const userSocketId = connectedUsers.get(callerId);
    const userSocket = getSocketById(userSocketId);
    if (userSocket) {
      userSocket.emit('call-rejected', {
        type: 'call-rejected',
        from: professionalId,
        to: callerId,
        timestamp: Date.now(),
      });
    }

    // Try to find another professional
    const available = findAvailableProfessional();
    if (available) {
      const { professionalId: newProfId, socketId: professionalSocketId } = available;

      const callId = uuidv4();
      activeCalls.set(callId, {
        userId: callerId,
        professionalId: newProfId,
        status: 'pending',
        createdAt: Date.now(),
      });

      const professionalSocket = getSocketById(professionalSocketId);
      if (professionalSocket) {
        professionalSocket.emit('call-request', {
          type: 'call-request',
          from: callerId,
          to: newProfId,
          callId,
          timestamp: Date.now(),
        });
      }
    }
  });

  // Generic message handler (for WebRTC signaling)
  socket.on('message', (message) => {
    const { to, type } = message;
    console.log(`Message ${type} from ${message.from} to ${to}`);

    // Find recipient socket
    let recipientSocketId = connectedUsers.get(to) || connectedProfessionals.get(to);

    // Fallback: check both maps
    if (!recipientSocketId) {
      for (const [id, socketId] of connectedUsers) {
        if (id === to) {
          recipientSocketId = socketId;
          break;
        }
      }
    }
    if (!recipientSocketId) {
      for (const [id, socketId] of connectedProfessionals) {
        if (id === to) {
          recipientSocketId = socketId;
          break;
        }
      }
    }

    if (recipientSocketId) {
      const recipientSocket = getSocketById(recipientSocketId);
      if (recipientSocket) {
        recipientSocket.emit('message', message);
      }
    } else {
      console.log(`Recipient not found: ${to}`);
    }
  });

  // Handle disconnection
  socket.on('disconnect', () => {
    console.log(`Client disconnected: ${socket.id}`);

    // Clean up user
    for (const [id, socketId] of connectedUsers) {
      if (socketId === socket.id) {
        connectedUsers.delete(id);

        // End any active calls for this user
        for (const [callId, call] of activeCalls) {
          if (call.userId === id) {
            const professionalSocketId = connectedProfessionals.get(call.professionalId);
            const professionalSocket = getSocketById(professionalSocketId);
            if (professionalSocket) {
              professionalSocket.emit('message', {
                type: 'call-ended',
                from: id,
                to: call.professionalId,
                timestamp: Date.now(),
              });
            }
            activeCalls.delete(callId);
          }
        }

        // Remove from waiting queue
        const waitingIndex = waitingUsers.indexOf(id);
        if (waitingIndex > -1) {
          waitingUsers.splice(waitingIndex, 1);
        }
        break;
      }
    }

    // Clean up professional
    for (const [id, socketId] of connectedProfessionals) {
      if (socketId === socket.id) {
        connectedProfessionals.delete(id);

        // End any active calls for this professional
        for (const [callId, call] of activeCalls) {
          if (call.professionalId === id) {
            const userSocketId = connectedUsers.get(call.userId);
            const userSocket = getSocketById(userSocketId);
            if (userSocket) {
              userSocket.emit('message', {
                type: 'call-ended',
                from: id,
                to: call.userId,
                timestamp: Date.now(),
              });
            }
            activeCalls.delete(callId);
          }
        }
        break;
      }
    }

    // Process waiting users in case a new professional is available
    processWaitingUsers();
  });
});

// Process waiting users queue
function processWaitingUsers() {
  while (waitingUsers.length > 0) {
    const available = findAvailableProfessional();
    if (!available) break;

    const callerId = waitingUsers.shift();
    const { professionalId, socketId: professionalSocketId } = available;

    const userSocketId = connectedUsers.get(callerId);
    if (!userSocketId) continue; // User disconnected

    // Create call session
    const callId = uuidv4();
    activeCalls.set(callId, {
      userId: callerId,
      professionalId,
      status: 'pending',
      createdAt: Date.now(),
    });

    // Notify professional
    const professionalSocket = getSocketById(professionalSocketId);
    if (professionalSocket) {
      professionalSocket.emit('call-request', {
        type: 'call-request',
        from: callerId,
        to: professionalId,
        callId,
        timestamp: Date.now(),
      });
    }

    // Notify user
    const userSocket = getSocketById(userSocketId);
    if (userSocket) {
      userSocket.emit('professional-available', {
        professionalId,
        callId,
      });
    }
  }
}

// Clean up stale calls periodically
setInterval(() => {
  const now = Date.now();
  const timeout = 5 * 60 * 1000; // 5 minutes

  for (const [callId, call] of activeCalls) {
    if (call.status === 'pending' && now - call.createdAt > timeout) {
      console.log(`Removing stale call: ${callId}`);
      activeCalls.delete(callId);
    }
  }
}, 60 * 1000); // Check every minute

// Start server
const PORT = process.env.PORT || 3001;
server.listen(PORT, () => {
  console.log(`Novaid Signaling Server running on port ${PORT}`);
  console.log(`Health check: http://localhost:${PORT}/health`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});
