# frozen_string_literal: true

class StorySample
  Image = Data.define(:url)
  Illustration = Data.define(:original_image)
  PageCollection = Class.new(Array) do
    def order(*)
      self
    end
  end
  Page = Data.define(:number, :text, :image, :alt) do
    def illustration
      Illustration.new(Image.new(image))
    end

    def persisted?
      false
    end
  end

  attr_reader :slug, :title, :reader_age, :art_style, :pages

  def initialize(attributes)
    @slug = attributes.fetch("slug")
    @title = attributes.fetch("title")
    @reader_age = attributes.fetch("reader_age")
    @art_style = attributes.fetch("art_style")
    @pages = PageCollection.new(attributes.fetch("pages").map { |page| Page.new(**page.symbolize_keys) })
  end

  def name
    title
  end

  def current_pages
    pages
  end

  def gift_preparable?
    false
  end

  def self.all
    @all ||= YAML.safe_load_file(Rails.root.join("config/story_samples.yml")).map { |attributes| new(attributes) }
  end

  def self.find(slug)
    all.find { |story| story.slug == slug }
  end
end
