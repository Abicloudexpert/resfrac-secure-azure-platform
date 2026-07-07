'use strict';

module.exports = {
  testEnvironment: 'node',
  collectCoverageFrom: ['src/**/*.js', '!src/server.js', '!src/telemetry.js'],
  coverageThreshold: {
    global: {
      statements: 70,
      branches: 55,
      functions: 70,
      lines: 70,
    },
  },
  coverageReporters: ['text', 'cobertura', 'lcov'],
  testMatch: ['**/test/**/*.test.js'],
};
