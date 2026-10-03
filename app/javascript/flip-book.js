// flip-book.js
import { PageFlip } from 'page-flip'

const initializedBooks = new WeakSet();

function initializeBook() {
    const bookEl = document.getElementById('storybook');
    if (!bookEl || initializedBooks.has(bookEl)) return;

    // Turbo must cache the original pages, not PageFlip's wrappers and clip paths.
    const cleanBook = bookEl.cloneNode(true);
    const pageFlip = new PageFlip(bookEl, {
        startPage: Number(bookEl.dataset.currentPage || 0),
        width: 550,
        height: 800,
        size: "stretch",
        showCover: true,
        usePortrait: true,
        drawShadow: true,
        flippingTime: 800,
        mobileScrollSupport: true,
        // Below an 840px reader, show one page. CSS lets it fit smaller phones.
        minWidth: 420,
        maxWidth: 550,
        minHeight: 100,
        maxHeight: 800
    });

    pageFlip.loadFromHTML(bookEl.querySelectorAll('.page'));

    const prevButton = document.getElementById('prevPage');
    const nextButton = document.getElementById('nextPage');
    const flipPrev = () => pageFlip.flipPrev();
    const flipNext = () => pageFlip.flipNext();
    prevButton?.addEventListener('click', flipPrev);
    nextButton?.addEventListener('click', flipNext);

    // Sidebar and container changes can resize the book without a window resize.
    const resizeObserver = new ResizeObserver(() => {
        if (bookEl.isConnected) pageFlip.update();
        else resizeObserver.disconnect();
    });
    resizeObserver.observe(bookEl);
    document.addEventListener('turbo:before-cache', () => {
        resizeObserver.disconnect();
        prevButton?.removeEventListener('click', flipPrev);
        nextButton?.removeEventListener('click', flipNext);
        cleanBook.dataset.currentPage = pageFlip.getCurrentPageIndex();
        bookEl.replaceWith(cleanBook);
        // destroy removes the old root too, so replace it before teardown.
        pageFlip.destroy();
    }, { once: true });

    const toggleState = () => {
        const index = pageFlip.getCurrentPageIndex();
        if (index === 0 || index === pageFlip.getPageCount() - 1) {
            bookEl.classList.add('is-closed');
        } else {
            bookEl.classList.remove('is-closed');
        }
    };

    pageFlip.on('changeState', (e) => {
        if (e.data === 'flipping') {
            bookEl.classList.add('is-flipping');
        } else if (e.data === 'read') {
            bookEl.classList.remove('is-flipping');
            toggleState();
        }
    });

    toggleState();
    initializedBooks.add(bookEl);
}

document.addEventListener("turbo:load", initializeBook);
document.addEventListener("turbo:before-stream-render", (event) => {
    const render = event.detail.render;
    event.detail.render = async function(...args) {
        await render.apply(this, args);
        initializeBook();
    };
});
