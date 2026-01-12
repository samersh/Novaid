module.exports = {
  dependencies: {
    // Explicitly disable react-native-maps for all platforms
    // This prevents any cached references from being used
    'react-native-maps': {
      platforms: {
        ios: null,
        android: null,
      },
    },
  },
};
