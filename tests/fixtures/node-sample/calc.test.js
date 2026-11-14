const test = require('node:test');
const assert = require('node:assert');
const { add } = require('./calc.js');

test('adds', () => {
  assert.strictEqual(add(2, 3), 5);
});
