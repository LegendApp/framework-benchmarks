const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');
const path = require('node:path');

module.exports = mergeConfig(getDefaultConfig(__dirname), {
  watchFolders: [path.resolve(__dirname, '../..')],
  resolver: {
    platforms: ['macos', 'native'],
    extraNodeModules: { 'react-native': path.dirname(require.resolve('react-native-macos/package.json')) },
    resolveRequest(context, moduleName, platform) {
      if (moduleName === 'react-native' || moduleName.startsWith('react-native/')) {
        moduleName = moduleName.replace(/^react-native/, 'react-native-macos');
      }
      return context.resolveRequest(context, moduleName, platform);
    },
  },
});
