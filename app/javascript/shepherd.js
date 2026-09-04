import Shepherd  from 'shepherd.js';

// "New" Book button, mainpage (/)
document.addEventListener("turbo:load", function (e) {
if(document.getElementsByClassName("new_book_tutorial").length > 0){
  const tour = new Shepherd.Tour({
  useModalOverlay: true,
  defaultStepOptions: {
    classes: 'shadow-md bg-purple-dark',
    scrollTo: true, 
    arrow: true
  }
  });

  tour.addStep({
    id: 'NewBook',
    text: I18n["tutorial"]["welcome"],
    arrow: true,
    attachTo: {
      element: '.new_book_tutorial',
      on: 'bottom'
    },
    classes: 'example-step-extra-class',
    buttons: [
      {
        text: I18n.tutorial.done,
        action: tour.next
      }
    ]
  });

  tour.start();
}});

// Creating Book, name (/books/new)
document.addEventListener("turbo:load", function () {
  if(document.getElementsByClassName("name_book_tutorial").length > 0){
  const tour = new Shepherd.Tour({
    useModalOverlay: true,
    defaultStepOptions: {
      classes: 'shadow-md bg-purple-dark',
      scrollTo: true, 
      arrow: true
    }
  });

  tour.addStep({
    id: 'NewBook',
    text: I18n.tutorial.create_book,
    arrow: true,
    attachTo: {
      element: '.name_book_tutorial',
      on: 'bottom'
    },
    classes: 'example-step-extra-class',
    buttons: [
      {
        text: I18n.tutorial.next,
        action: tour.next
      }
    ]
  });
  tour.addStep({
    id: 'NewBook',
    text: I18n.tutorial.create_book_finish,
    arrow: true,
    attachTo: {
      element: '.submit',
      on: 'bottom'
    },
    classes: 'example-step-extra-class',
    buttons: [
      {
        text: I18n.tutorial.back,
        action() {
            return this.back();
          },
      },
      {
        text: I18n.tutorial.done,
        action: tour.next
      }
    ]
  });
    
  tour.start();
  }
})

// Creating characters overview (/books/{id})
document.addEventListener("turbo:load", function () {
  if(document.getElementsByClassName("character_overview_tutorial").length > 0){
  const tour = new Shepherd.Tour({
    useModalOverlay: true,
    defaultStepOptions: {
      classes: 'shadow-md bg-purple-dark',
      scrollTo: true, 
      arrow: true
    }
  });

  tour.addStep({
    id: 'NewBook',
    text: I18n.tutorial.create_character,
    arrow: true,
    attachTo: {
      element: '.character_overview_tutorial',
      on: 'bottom'
    },
    classes: 'example-step-extra-class',
    buttons: [
      {
        text: I18n.tutorial.next,
        action: tour.next
      }
    ]
  });
  tour.addStep({
    id: 'NewBook',
    text: I18n.tutorial.reuse_character,
    arrow: true,
    attachTo: {
      element: '.reuse_character',
      on: 'bottom'
    },
    classes: 'example-step-extra-class',
    buttons: [
      {
        text: I18n.tutorial.back,
        action() {
            return this.back();
          },
      },
      {
        text: I18n.tutorial.next,
        action: tour.next
      }
    ]
  });

   tour.addStep({
    id: 'NewBook',
    text: I18n.tutorial.character_generation,
    arrow: true,
    attachTo: {
      element: '.character_generation_area',
      on: 'bottom'
    },
    classes: 'example-step-extra-class',
    buttons: [
      {
        text: I18n.tutorial.back,
        action() {
            return this.back();
          },
      },
      {
        text: I18n.tutorial.next,
        action: tour.next
      }
    ]
  });

  tour.addStep({
    id: 'NewBook',
    text: I18n.tutorial.ready,
    arrow: true,
    attachTo: {
      element: '.tutorial_make_book',
      on: 'bottom'
    },
    classes: 'example-step-extra-class',
    buttons: [
      {
        text: I18n.tutorial.back,
        action() {
            return this.back();
          },
      },
      {
        text: I18n.tutorial.done,
        action: tour.next
      }
    ]
  });
    
  tour.start();
}})

// New character (/characters/new)
document.addEventListener("turbo:frame-load", function (e) {
  let frame = document.getElementById("character_modal");
  if (frame.loaded) { if(document.getElementsByClassName("new_character_tutorial").length > 0){
    const tour = new Shepherd.Tour({
      useModalOverlay: true,
      defaultStepOptions: {
        classes: 'shadow-md bg-purple-dark',
        scrollTo: true, 
        arrow: true
      }
    });

    tour.addStep({
      id: 'NewBook',
      text: I18n.tutorial.character_creation,
      arrow: true,
      attachTo: {
        element: '.new_character_tutorial',
        on: 'bottom'
      },
      classes: 'example-step-extra-class',
      buttons: [
        {
          text: I18n.tutorial.next,
          action: tour.next
        }
      ]
    });
    tour.addStep({
      id: 'NewBook',
      text: I18n.tutorial.character_looks,
      arrow: true,
      attachTo: {
        element: '.character_looks',
        on: 'bottom'
      },
      classes: 'example-step-extra-class',
      buttons: [
        {
          text: I18n.tutorial.back,
          action() {
              return this.back();
            },
        },
        {
          text: I18n.tutorial.next,
          action: tour.next
        }
      ]
    });

    tour.addStep({
      id: 'NewBook',
      text: I18n.tutorial.character_attributes,
      arrow: true,
      attachTo: {
        element: '.character_attributes',
        on: 'bottom'
      },
      classes: 'example-step-extra-class',
      buttons: [
        {
          text: I18n.tutorial.back,
          action() {
              return this.back();
            },
        },
        {
          text: I18n.tutorial.next,
          action: tour.next
        }
      ]
    });

    tour.addStep({
      id: 'NewBook',
      text: I18n.tutorial.character_ready,
      arrow: true,
      attachTo: {
        element: '.character_ready',
        on: 'bottom'
      },
      classes: 'example-step-extra-class',
      buttons: [
        {
          text: I18n.tutorial.back,
          action() {
              return this.back();
            },
        },
        {
          text: I18n.tutorial.done,
          action: tour.next
        }
      ]
    });
      
    tour.start();
  }}
})

// Select Characters (/characters/select)
document.addEventListener("turbo:frame-load", function (e) {
  let frame = document.getElementById("character_select_modal");
  if (frame.loaded) { 
    if(document.getElementsByClassName("select_character_tutorial").length > 0){
        const tour = new Shepherd.Tour({
        useModalOverlay: true,
        defaultStepOptions: {
          classes: 'shadow-md bg-purple-dark',
          scrollTo: true, 
          arrow: true
        }
      });

      tour.addStep({
        id: 'NewBook',
        text: I18n.tutorial.character_select,
        arrow: true,
        attachTo: {
          element: '.character_select',
          on: 'bottom'
        },
        classes: 'example-step-extra-class',
        buttons: [
          {
            text: I18n.tutorial.next,
            action: tour.next
          }
        ]
      });
      tour.addStep({
        id: 'NewBook',
        text: I18n.tutorial.character_select_ready,
        arrow: true,
        attachTo: {
          element: '.submit',
          on: 'bottom'
        },
        classes: 'example-step-extra-class',
        buttons: [
          {
            text: I18n.tutorial.back,
            action() {
                return this.back();
              },
          },
          {
            text: I18n.tutorial.done,
            action: tour.next
          }
        ]
      });

      tour.start();
  
    }
  }
})


// Finish Book plot (/book/update)
document.addEventListener("turbo:frame-load", function (e) {
  let frame = document.getElementById("book_modal");
  if (frame.loaded) { 
    if(document.getElementsByClassName("book_plot_tutorial").length > 0){
        const tour = new Shepherd.Tour({
        useModalOverlay: true,
        defaultStepOptions: {
          classes: 'shadow-md bg-purple-dark',
          scrollTo: true, 
          arrow: true
        }
      });

      tour.addStep({
        id: 'NewBook',
        text: I18n.tutorial.book_plot,
        arrow: true,
        attachTo: {
          element: '.book_plot_tutorial',
          on: 'bottom'
        },
        classes: 'example-step-extra-class',
        buttons: [
          {
            text: I18n.tutorial.next,
            action: tour.next
          }
        ]
      });
      tour.addStep({
        id: 'NewBook',
        text: I18n.tutorial.book_ready,
        arrow: true,
        attachTo: {
          element: '.submit',
          on: 'bottom'
        },
        classes: 'example-step-extra-class',
        buttons: [
          {
            text: I18n.tutorial.back,
            action() {
                return this.back();
              },
          },
          {
            text: I18n.tutorial.done,
            action: tour.next
          }
        ]
      });

      tour.start();
  
    }
  }
})