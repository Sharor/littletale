const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

test('initializes a completed book inserted by Turbo, only once per element', async () => {
  const listeners = {};
  let book = null;
  let instances = 0;
  const pages = [{}, {}];
  const document = {
    addEventListener: (name, handler) => { listeners[name] = handler; },
    getElementById: (id) => id === 'storybook' ? book : null,
    querySelectorAll: () => pages
  };
  class PageFlip {
    constructor(element) { assert.equal(element, book); instances++; }
    loadFromHTML(elements) { assert.equal(elements, pages); }
    getCurrentPageIndex() { return 0; }
    getPageCount() { return 2; }
    on() {}
  }
  const source = fs.readFileSync('app/javascript/flip-book.js', 'utf8')
    .replace(/import .* from 'page-flip'/, '');
  vm.runInNewContext(source, { document, window: { innerWidth: 1200 }, PageFlip });
  listeners['turbo:load']();
  assert.equal(instances, 0);

  const event = { detail: { render: async () => {
    book = { classList: { add() {}, remove() {} } };
  } } };
  listeners['turbo:before-stream-render']?.(event);
  await event.detail.render();
  assert.equal(instances, 1, 'the newly inserted book must initialize without navigation');
  listeners['turbo:load']();
  assert.equal(instances, 1, 'an initialized book must not initialize twice');
});
