module.exports = {
  dependencies: {
    'react-native-maps': {
      platforms: {
        ios: null, // Disable autolinking for iOS to avoid get_folly_config error
      },
    },
  },
};
