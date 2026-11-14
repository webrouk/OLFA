module.exports = {
  rootDir: '.',
  testMatch: ['<rootDir>/test/unit/**/*.test.ts'],
  transform: { '^.+\\.ts$': ['ts-jest', { tsconfig: 'tsconfig.unit.json', isolatedModules: true }] },
  testEnvironment: 'node',
};
