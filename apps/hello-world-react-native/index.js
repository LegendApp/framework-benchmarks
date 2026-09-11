import React from 'react';
import { AppRegistry, StyleSheet, Text, View } from 'react-native';

const styles = StyleSheet.create({
  root: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: '#ffffff' },
  text: { fontSize: 32, color: '#202124' },
});

function HelloWorld() {
  return <View style={styles.root}><Text style={styles.text}>Hello, world!</Text></View>;
}

AppRegistry.registerComponent('HelloWorld', () => HelloWorld);
