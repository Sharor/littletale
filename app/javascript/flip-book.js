// flip-book.js
import { PageFlip } from 'page-flip'

document.addEventListener("turbo:load", function() {
    const bookEl = document.getElementById('storybook');
    if (!bookEl) return;

    const isMobile = window.innerWidth < 768;

    // Force a specific aspect ratio for mobile portrait
    const pageWidth = isMobile ? window.innerWidth - 20 : 550;
    const pageHeight = isMobile ? 650 : 800;

    const pageFlip = new PageFlip(bookEl, {
        width: pageWidth,
        height: pageHeight,
        size: "stretch",
        showCover: true,
        usePortrait: isMobile, // [cite: 1]
        drawShadow: !isMobile, 
        flippingTime: 800,
        mobileScrollSupport: true,
        // Add this to prevent the "miniature" scale-down
        minWidth: isMobile ? 300 : 550,
        minHeight: isMobile ? 450 : 800
    });

    pageFlip.loadFromHTML(document.querySelectorAll('.page'));

    document.getElementById('prevPage')?.addEventListener('click', () => {
        pageFlip.flipPrev();
    });

    document.getElementById('nextPage')?.addEventListener('click', () => {
        pageFlip.flipNext();
    });

    // Re-calculates and forces a redraw for mobile
    if (isMobile) {
        pageFlip.updateFromHtml(document.querySelectorAll('.page'));
    }

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
});