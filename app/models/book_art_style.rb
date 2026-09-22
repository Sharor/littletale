# frozen_string_literal: true

class BookArtStyle
  Style = Data.define(:key, :name, :preview, :prompt)
  DEFAULT_KEY = "western_book_style"

  STYLES = [
    Style.new(
      key: "western_book_style",
      name: "Western Book Style",
      preview: "art_styles/western_book_style.webp",
      prompt: "Western children's book illustration with warm, painterly color, expressive natural characters, gentle texture, and cinematic storybook composition."
    ),
    Style.new(
      key: "whimsical_storybook",
      name: "Whimsical Storybook",
      preview: "art_styles/whimsical_storybook.webp",
      prompt: "Whimsical children's storybook illustration with playful proportions, imaginative details, soft organic shapes, luminous color, and a warm sense of wonder."
    ),
    Style.new(
      key: "storybook_watercolor",
      name: "Storybook Watercolor",
      preview: "art_styles/storybook_watercolor.webp",
      prompt: "Traditional storybook watercolor illustration with translucent washes, softly bleeding edges, visible paper texture, delicate linework, and gentle layered color."
    ),
    Style.new(
      key: "cute_cartoon",
      name: "Cute Cartoon",
      preview: "art_styles/cute_cartoon.webp",
      prompt: "Cute children's cartoon illustration with rounded expressive characters, clean shapes, bright friendly color, soft shading, and playful readable expressions."
    ),
    Style.new(
      key: "colored_pencil",
      name: "Colored Pencil",
      preview: "art_styles/colored_pencil.webp",
      prompt: "Hand-drawn colored-pencil children's book illustration with visible pencil grain, layered strokes, lightly sketched contours, warm paper texture, and rich handmade color."
    ),
    Style.new(
      key: "cut_paper_collage",
      name: "Cut-Paper Collage",
      preview: "art_styles/cut_paper_collage.webp",
      prompt: "Cut-paper collage children's book illustration made from layered paper shapes, tactile fibers, crisp cut edges, subtle cast shadows, and bold handcrafted color."
    ),
    Style.new(
      key: "rounded_3d_animation",
      name: "Rounded 3D Animation",
      preview: "art_styles/rounded_3d_animation.webp",
      prompt: "Polished rounded 3D animated children's film style with appealing stylized forms, expressive faces, soft materials, warm cinematic lighting, and colorful dimensional environments."
    ),
    Style.new(
      key: "comic_book",
      name: "Comic Book",
      preview: "art_styles/comic_book.webp",
      prompt: "All-ages comic-book illustration with confident ink contours, dynamic framing, energetic poses, bold color blocks, controlled halftone texture, and clear visual storytelling."
    ),
    Style.new(
      key: "superhero_comic",
      name: "Superhero Comic",
      preview: "art_styles/superhero_comic.webp",
      prompt: "Vibrant all-ages superhero comic illustration with bold black inks, saturated primary colors, dramatic action framing, heroic energy, dynamic perspective, and classic printed-comic texture."
    ),
    Style.new(
      key: "gouache_storybook",
      name: "Gouache Storybook",
      preview: "art_styles/gouache_storybook.webp",
      prompt: "Gouache children's storybook illustration with opaque matte paint, visible brushwork, layered shapes, rich velvety color, and charming hand-painted detail."
    ),
    Style.new(
      key: "claymation_plasticine",
      name: "Claymation / Plasticine",
      preview: "art_styles/claymation_plasticine.webp",
      prompt: "Claymation and plasticine children's animation style with hand-sculpted rounded forms, tactile clay texture, tiny crafted sets, soft studio lighting, and a delightful stop-motion appearance."
    ),
    Style.new(
      key: "retro_childrens_book",
      name: "Retro Children’s Book",
      preview: "art_styles/retro_childrens_book.webp",
      prompt: "Mid-century retro children's book illustration with simplified shapes, vintage print texture, restrained period color, expressive ink work, and charming 1950s–1960s composition."
    )
  ].freeze

  BY_KEY = STYLES.index_by(&:key).freeze

  class << self
    def all = STYLES
    def keys = BY_KEY.keys
    def fetch(key) = BY_KEY.fetch(key)
    def find(key) = BY_KEY[key]
    def default = fetch(DEFAULT_KEY)
  end
end
