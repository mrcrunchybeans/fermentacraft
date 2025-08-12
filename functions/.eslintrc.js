/* functions/.eslintrc.js */
module.exports = {
  root: true,
  env: { node: true, es2020: true },
  ignorePatterns: ['lib/**', 'node_modules/**'],
  // Lint JS with the default parser/rules
  extends: ['eslint:recommended'],
  overrides: [
    {
      // Apply TypeScript parser/rules only to TS files
      files: ['**/*.ts'],
      parser: '@typescript-eslint/parser',
      parserOptions: {
        // Only point at tsconfig if you actually have TS source
        project: ['./tsconfig.json'],
        tsconfigRootDir: __dirname,
      },
      plugins: ['@typescript-eslint'],
      extends: ['plugin:@typescript-eslint/recommended'],
    },
  ],
};
