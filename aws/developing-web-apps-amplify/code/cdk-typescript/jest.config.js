module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/test', '<rootDir>/lib', '<rootDir>/lambda'],
  testMatch: ['**/__tests__/**/*.ts', '**/*.(test|spec).ts'],
  transform: {
    '^.+\\.tsx?$': 'ts-jest',
  },
  collectCoverageFrom: [
    'lib/**/*.ts',
    'lambda/**/*.ts',
    '!lib/**/*.d.ts',
    '!**/__tests__/**',
    '!**/node_modules/**',
  ],
  coverageDirectory: 'coverage',
  coverageReporters: ['text', 'lcov', 'html'],
  coverageThreshold: {
    global: {
      branches: 70,
      functions: 70,
      lines: 70,
      statements: 70,
    },
  },
  setupFilesAfterEnv: [],
  testTimeout: 30000,
  verbose: true,
  clearMocks: true,
  restoreMocks: true,
};