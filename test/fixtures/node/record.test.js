const assert = require("node:assert");
const test = require("node:test");

test("the fixture has a test, whose coverage Sonar reads", () => {
  assert.strictEqual(1 + 1, 2);
});
