// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./controllers"
import 'page-flip'

document.addEventListener("turbo:load", () => {
  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('opacity-100', 'translate-y-0');
        entry.target.classList.remove('opacity-0', 'translate-y-10');
      }
    });
  }, { threshold: 0.1 });

  document.querySelectorAll('.reveal-on-scroll').forEach((el) => {
    el.classList.add('transition', 'duration-700', 'ease-out', 'opacity-0', 'translate-y-10');
    observer.observe(el);
  });
});

document.addEventListener("turbo:before-stream-render", (event) => {
  // Check if the incoming stream is finishing the book
  const template = event.detail.newStream.querySelector("template")
  if (template && template.content.querySelector(".animate-magical-reveal")) {
    createSparkles();
  }
});

function createSparkles() {
  const container = document.querySelector("[id^='book_']");
  for (let i = 0; i < 20; i++) {
    const sparkle = document.createElement("div");
    sparkle.className = "absolute pointer-events-none bg-yellow-200 rounded-full";
    sparkle.style.width = sparkle.style.height = Math.random() * 5 + "px";
    sparkle.style.left = Math.random() * 100 + "%";
    sparkle.style.top = Math.random() * 100 + "%";
    
    container.appendChild(sparkle);
    
    sparkle.animate([
      { transform: "translateY(0) scale(1)", opacity: 1 },
      { transform: `translateY(-50px) scale(0)`, opacity: 0 }
    ], { duration: 1000 + Math.random() * 1000, easing: "ease-out" }).onfinish = () => sparkle.remove();
  }
}

document.addEventListener("turbo:before-stream-render", (event) => {
  const isNowCompleted = event.detail.newStream.innerHTML.includes('completed');
  
  if (isNowCompleted) {
    const castle = document.querySelector(".in-progress svg");
    if (castle) {
      // Add a scale-down effect before the new content arrives
      castle.style.transition = "transform 0.8s ease-in-out, opacity 0.8s";
      castle.style.transform = "scale(0.5) translateY(-20px)";
      castle.style.opacity = "0.5";
    }
  }
});