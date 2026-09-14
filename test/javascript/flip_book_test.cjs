const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function readerHarness() {
  const listeners = {};
  const instances = [];
  const observers = [];
  const pages = [{}, {}, {}, {}];
  const controls = {};
  let book = null;
  const document = {
    addEventListener: (name, handler) => { listeners[name] = handler; },
    getElementById: (id) => id === 'storybook' ? book : {
      addEventListener: (_event, handler) => { controls[id] = handler; }
    },
    querySelectorAll: () => [...pages, { unrelatedPage: true }]
  };
  class PageFlip {
    constructor(element, settings) {
      assert.equal(element, book);
      this.settings = settings;
      this.currentPage = 0;
      this.updates = 0;
      instances.push(this);
    }
    loadFromHTML(elements) { this.pages = elements; }
    getCurrentPageIndex() { return this.currentPage; }
    getPageCount() { return this.pages.length; }
    flipNext() { this.currentPage++; }
    flipPrev() { this.currentPage--; }
    update() { this.updates++; }
    on() {}
  }
  class ResizeObserver {
    constructor(callback) { this.callback = callback; observers.push(this); }
    observe(element) { this.element = element; }
    disconnect() { this.disconnected = true; }
  }
  const source = fs.readFileSync('app/javascript/flip-book.js', 'utf8')
    .replace(/import .* from 'page-flip'/, '');
  vm.runInNewContext(source, { document, window: { innerWidth: 1200 }, PageFlip, ResizeObserver });
  const insertBook = () => {
    book = {
      clientWidth: 704,
      isConnected: true,
      classList: { add() {}, remove() {} },
      querySelectorAll: () => pages
    };
    return book;
  };
  return { listeners, instances, observers, pages, controls, insertBook };
}

test('initializes a completed book inserted by Turbo, only once per element', async () => {
  const { listeners, instances, insertBook } = readerHarness();
  listeners['turbo:load']();
  assert.equal(instances.length, 0);

  const event = { detail: { render: async () => { insertBook(); } } };
  listeners['turbo:before-stream-render']?.(event);
  await event.detail.render();
  assert.equal(instances.length, 1, 'the newly inserted book must initialize without navigation');
  listeners['turbo:load']();
  assert.equal(instances.length, 1, 'an initialized book must not initialize twice');
});

test('permits a single readable page beside the sidebar and a spread when space allows', () => {
  const { listeners, instances, insertBook } = readerHarness();
  const book = insertBook();
  listeners['turbo:load']();
  const settings = instances[0].settings;

  assert.equal(settings.usePortrait, true, 'a wide viewport may still contain a narrow reader');
  assert.ok(settings.minWidth * 2 > book.clientWidth, 'a 704px reader must show one page');
  assert.ok(settings.minWidth * 2 <= 1100, 'the original desktop spread must still fit');
  assert.ok(settings.minHeight < 450, 'small pages must not be forced to 800px tall');
  assert.equal(settings.maxWidth, 550, 'wide screens must not enlarge the original pages');
});

test('loads only this book’s pages, leaving unrelated page elements in place', () => {
  const { listeners, instances, insertBook, pages } = readerHarness();
  insertBook();
  listeners['turbo:load']();
  assert.equal(instances[0].pages, pages);
});

test('redraws after container resizing without resetting the page or duplicating controls', () => {
  const { listeners, instances, observers, insertBook, controls } = readerHarness();
  const book = insertBook();
  listeners['turbo:load']();
  controls.nextPage();
  assert.equal(instances[0].currentPage, 1);

  assert.equal(observers.length, 1, 'the reader must observe its own available size');
  assert.equal(observers[0].element, book);
  book.clientWidth = 350;
  observers[0].callback();
  assert.equal(instances.length, 1);
  assert.equal(instances[0].updates, 1);
  assert.equal(instances[0].currentPage, 1, 'resizing must retain the reading position');
  controls.nextPage();
  controls.prevPage();
  assert.equal(instances[0].currentPage, 1);

  listeners['turbo:before-cache']();
  assert.equal(observers[0].disconnected, true, 'navigation must release the resize observer');
});
