# frozen_string_literal: true

require "prawn"

module Lulu
  class BookletPdf
    class PageLimitExceeded < StandardError; end
    class RenderingError < StandardError; end

    Result = Data.define(:interior, :cover, :page_count, :blank_page_count)

    POINTS_PER_INCH = 72
    INTERIOR_SIZE = [ 5.25 * POINTS_PER_INCH, 8.25 * POINTS_PER_INCH ].freeze
    COVER_SIZE = [ 10.25 * POINTS_PER_INCH, 8.25 * POINTS_PER_INCH ].freeze
    SAFE_MARGIN = 0.5 * POINTS_PER_INCH
    MAX_ILLUSTRATION = 3.4 * POINTS_PER_INCH
    MAX_PAGES = 48
    IMAGE_PARSER_ERRORS = [
      Prawn::Errors::UnsupportedImageType,
      Prawn::Images::JPG::FormatError,
      Zlib::DataError,
      EOFError,
      ArgumentError,
      TypeError,
      NoMethodError
    ].freeze
    FONT_PARSER_ERRORS = [
      Prawn::Errors::UnknownFont,
      TTFunk::Error,
      TTFunk::SubTable::EOTError,
      TTFunk::UnresolvedPlaceholderError,
      TTFunk::DuplicatePlaceholderError,
      TTFunk::Table::Cff::Dict::InvalidOperandError,
      TTFunk::Table::Cff::Dict::TooManyOperandsError,
      EOFError,
      ArgumentError,
      IndexError,
      TypeError,
      NoMethodError,
      NotImplementedError
    ].freeze

    def initialize(order)
      @order = order
    end

    def render
      interior, page_count, blank_page_count = render_interior
      Result.new(
        interior:,
        cover: render_cover,
        page_count:,
        blank_page_count:
      )
    rescue Prawn::Errors::CannotFit, Prawn::Errors::IncompatibleStringEncoding,
           TTFunk::Error, TTFunk::SubTable::EOTError, TTFunk::UnresolvedPlaceholderError,
           TTFunk::DuplicatePlaceholderError, TTFunk::Table::Cff::Dict::InvalidOperandError,
           TTFunk::Table::Cff::Dict::TooManyOperandsError, Errno::ENOENT => error
      raise RenderingError, error.message
    end

    private

    attr_reader :order

    def render_interior
      document = document_for(INTERIOR_SIZE)
      render_title_page(document)
      order.print_order_pages.each { |page| render_story_page(document, page) }
      render_end_page(document)

      blank_page_count = (4 - (document.page_count % 4)) % 4
      final_page_count = document.page_count + blank_page_count
      raise PageLimitExceeded, "The booklet exceeds Lulu's 48-page saddle-stitch limit" if final_page_count > MAX_PAGES

      blank_page_count.times { document.start_new_page }
      [ render_document(document), final_page_count, blank_page_count ]
    end

    def render_title_page(document)
      document.start_new_page
      paper_background(document)
      select_font(document, "EB Garamond")
      document.fill_color "742D38"
      render_text(
        document,
        :text_box,
        order.title,
        at: [ SAFE_MARGIN, INTERIOR_SIZE.last - 2.5 * POINTS_PER_INCH ],
        width: INTERIOR_SIZE.first - (2 * SAFE_MARGIN),
        height: 2 * POINTS_PER_INCH,
        align: :center,
        valign: :center,
        size: 28,
        overflow: :shrink_to_fit,
        min_font_size: 14
      )
    end

    def render_story_page(document, page)
      document.start_new_page
      paper_background(document)
      document.bounding_box(
        [ SAFE_MARGIN, INTERIOR_SIZE.last - SAFE_MARGIN ],
        width: INTERIOR_SIZE.first - (2 * SAFE_MARGIN),
        height: INTERIOR_SIZE.last - (2 * SAFE_MARGIN)
      ) do
        embed_image(
          document,
          page.image.download,
          fit: [ MAX_ILLUSTRATION, MAX_ILLUSTRATION ],
          position: :center
        )
        document.move_down 16
        select_font(document, "Inter")
        document.fill_color "302820"
        render_text(document, :text, page.text, size: 11, leading: 4, align: :left)
      end
    end

    def render_end_page(document)
      document.start_new_page
      paper_background(document)
      select_font(document, "EB Garamond")
      document.fill_color "742D38"
      render_text(
        document,
        :text_box,
        I18n.t("books.reader.the_end", locale: order.language.presence_in(I18n.available_locales.map(&:to_s)) || :en),
        at: [ SAFE_MARGIN, INTERIOR_SIZE.last / 2.0 ],
        width: INTERIOR_SIZE.first - (2 * SAFE_MARGIN),
        height: POINTS_PER_INCH,
        align: :center,
        size: 24
      )
    end

    def render_cover
      document = document_for(COVER_SIZE)
      document.start_new_page
      paper_background(document, size: COVER_SIZE)
      fold = COVER_SIZE.first / 2.0

      select_font(document, "EB Garamond")
      document.fill_color "742D38"
      render_text(
        document,
        :text_box,
        order.title,
        at: [ fold + SAFE_MARGIN, COVER_SIZE.last - 1.25 * POINTS_PER_INCH ],
        width: fold - (2 * SAFE_MARGIN),
        height: 1.5 * POINTS_PER_INCH,
        align: :center,
        valign: :center,
        size: 25,
        overflow: :shrink_to_fit,
        min_font_size: 13
      )

      cover_page = order.print_order_pages.detect { |page| page.image.attached? }
      if cover_page
        embed_image(
          document,
          cover_page.image.download,
          fit: [ 2.8 * POINTS_PER_INCH, 2.8 * POINTS_PER_INCH ],
          at: [ fold + ((fold - 2.8 * POINTS_PER_INCH) / 2.0), COVER_SIZE.last - 3 * POINTS_PER_INCH ]
        )
      end

      select_font(document, "Inter")
      document.fill_color "786044"
      render_text(
        document,
        :text_box,
        "MinorTale",
        at: [ SAFE_MARGIN, SAFE_MARGIN + 18 ],
        width: fold - (2 * SAFE_MARGIN),
        height: 24,
        align: :center,
        size: 9
      )
      render_document(document)
    end

    def embed_image(document, image_data, **options)
      document.image(StringIO.new(image_data), **options)
    rescue *IMAGE_PARSER_ERRORS => error
      raise RenderingError, error.message
    end

    def select_font(document, name)
      with_font_parser_handling { document.font(name) }
    end

    def render_text(document, method, text, **options)
      with_font_parser_handling { document.public_send(method, text, **options) }
    end

    def render_document(document)
      with_font_parser_handling { document.render }
    end

    def with_font_parser_handling
      yield
    rescue *FONT_PARSER_ERRORS => error
      raise RenderingError, error.message
    end

    def document_for(size)
      Prawn::Document.new(page_size: size, margin: 0, skip_page_creation: true, info: {
        Title: order.title,
        Creator: "MinorTale",
        Producer: "MinorTale Lulu sandbox integration"
      }).tap do |document|
        document.font_families.update(
          "Inter" => { normal: font_path("Inter.ttf") },
          "EB Garamond" => { normal: font_path("EBGaramond.ttf") }
        )
      end
    end

    def paper_background(document, size: INTERIOR_SIZE)
      document.fill_color "FFF9EB"
      document.fill_rectangle [ 0, size.last ], size.first, size.last
    end

    def font_path(filename)
      Rails.root.join("app/assets/fonts/print", filename).to_s
    end
  end
end
