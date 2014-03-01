# encoding: utf-8

require 'prawn'
require 'nokogiri'

module DocBook2PDF

  class Filter < ::Nanoc::Filter

    identifier :docbook2pdf
    type :text => :binary

    def run(content, params={})
      doc = Nokogiri::XML.parse(content)

      Prawn::Document.generate(output_filename) do |pdf|
        pdf.font_families.update("PT Sans" => {
          normal:      "fonts/PT-Sans/PTS55F.ttf",
          italic:      "fonts/PT-Sans/PTS56F.ttf",
          bold:        "fonts/PT-Sans/PTS75F.ttf",
          bold_italic: "fonts/PT-Sans/PTS76F.ttf",
        })
        pdf.font_families.update("Gentium Basic" => {
          normal:      "fonts/GentiumBasic_1102/GenBasR.ttf",
          italic:      "fonts/GentiumBasic_1102/GenBasI.ttf",
          bold:        "fonts/GentiumBasic_1102/GenBasB.ttf",
          bold_italic: "fonts/GentiumBasic_1102/GenBasBI.ttf",
        })
        pdf.font_families.update("Cousine" => {
          normal:      "fonts/cousine/Cousine-Regular.ttf",
          italic:      "fonts/cousine/Cousine-Italic.ttf",
          bold:        "fonts/cousine/Cousine-Bold.ttf",
          bold_italic: "fonts/cousine/Cousine-BoldItalic.ttf",
        })

        pdf.font 'Gentium Basic'
        pdf.font_size 12
        pdf.default_leading 2

        state = State.new

        RootRenderer.new(doc, pdf, state).process
      end
    end

  end

  class State

    attr_accessor :move_down
    attr_reader :chapters
    attr_reader :sections
    attr_reader :current_chapter
    attr_reader :current_figure

    def initialize
      @move_down = 0

      @current_chapter = 1
      @chapters = []

      @current_section = 1
      @sections = []

      @current_figure = 1
    end

    def add_chapter(title, page)
      @chapters << [ page, title, @current_chapter ]
      @current_chapter += 1

      @sections << [ page, nil,   @current_section ]
      @current_section += 1

      @current_figure = 1
    end

    def add_section(title, page)
      @sections << [ page, title, @current_section ]
      @current_section = 1
    end

    def add_figure
      @current_figure = 1
    end

  end

  class NodeRenderer

    def initialize(node, pdf, state)
      @node  = node
      @pdf   = pdf
      @state = state
    end

    def process
      raise 'abstract'
    end

    def handle_top_margin(x)
      @pdf.move_down([ x, @state.move_down ].max)
      @state.move_down = 0
    end

    def handle_bottom_margin(x)
      @state.move_down = x
    end

    def notify_unhandled(node)
      puts "*** #{self.class.to_s}: unhandled element: #{node.name}"
    end

  end

  class RootRenderer < NodeRenderer

    def process
      @node.children.each do |node|
        klass = case node.name
        when 'book'
          BookRenderer
        end

        if klass
          klass.new(node, @pdf, @state).process
        else
          notify_unhandled(node)
        end
      end
    end

  end

  class BookRenderer < NodeRenderer

    def process
      @node.children.each do |node|
        next if node.text?

        klass = case node.name
        when 'chapter'
          ChapterRenderer
        end

        if klass
          @pdf.repeat(:all, dynamic: true) do
            @pdf.stroke_horizontal_line(50, @pdf.bounds.width - 50, at: 20)
            at = [ 50, 14 ]
            @pdf.font('PT Sans', size: 10) do
              current_chapter = @state.chapters.reverse_each.with_index.find { |e,i| e[0] <= @pdf.page_number }
              current_section = @state.sections.reverse_each.with_index.find { |e,i| e[0] <= @pdf.page_number }

              text = ''
              if @pdf.page_number.even?
                text << @pdf.page_number.to_s
                text << '   |   '
                text << "Chapter #{current_chapter[0][2]}: #{current_chapter[0][1]}"
                align = :left
              else
                text << "#{current_section[0][1]}"
                text << '   |   '
                text << @pdf.page_number.to_s
                align = :right
              end
              @pdf.text_box(text, at: at, size: 9, width: @pdf.bounds.width - 100, align: align)
            end
          end

          @pdf.bounding_box([ 50, @pdf.bounds.height - 30 ], width: @pdf.bounds.width - 100, height: @pdf.bounds.height - 70) do
            klass.new(node, @pdf, @state).process
          end
        else
          notify_unhandled(node)
        end
      end
    end

  end

  class ChapterRenderer < NodeRenderer

    def process
      titles, nontitles = @node.children.partition do |e|
        e.name == 'title'
      end
      render_titles(titles)
      render_nontitles(nontitles)

      @pdf.start_new_page
    end

    def render_titles(titles)
      if titles.size != 1
        raise 'not enough titles or too many'
      end

      ChapterTitleRenderer.new(titles[0], @pdf, @state).process
    end

    def render_nontitles(nontitles)
      nontitles.each do |node|
        next if node.text?

        klass = case node.name
        when 'section'
          SectionRenderer
        when 'simpara'
          SimparaRenderer
        end

        if klass
          klass.new(node, @pdf, @state).process
        else
          notify_unhandled(node)
        end
      end
    end

  end

  class ChapterTitleRenderer < NodeRenderer

    def process
      handle_top_margin(0)

      text = @node.children.find { |e| e.text? }

      @pdf.bounding_box([0, @pdf.bounds.height - 50], width: @pdf.bounds.width) do
        @pdf.font('PT Sans', size: 32, style: :bold) do
          @pdf.text text.text, align: :right
        end
      end
      @state.add_chapter(text.text, @pdf.page_number)

      handle_bottom_margin(100)
    end

  end

  class SectionRenderer < NodeRenderer

    def process
      @node.children.each do |node|
        next if node.text?

        klass = case node.name
        when 'simpara'
          SimparaRenderer
        when 'programlisting'
          ProgramListingRenderer
        when 'screen'
          ScreenRenderer
        when 'title'
          section_title_renderer_class
        when 'note'
          NoteRenderer
        when 'section'
          SubsectionRenderer
        when 'figure'
          FigureRenderer
        end

        if klass
          @pdf.indent(indent, indent) do
            klass.new(node, @pdf, @state).process
          end
        else
          notify_unhandled(node)
        end
      end

      handle_bottom_margin(20)
    end

    def indent
      0
    end

    def section_title_renderer_class
      SectionTitleRenderer
    end

  end

  class SectionTitleRenderer < NodeRenderer

    def process
      handle_top_margin(30)

      text = @node.children.find { |e| e.text? }

      @pdf.indent(indent, indent) do
        @pdf.formatted_text [ { text: text.text, font: 'PT Sans', styles: [ :bold ], size: font_size } ]
      end
      handle_bottom_margin(10)
      @state.add_section(text.text, @pdf.page_number)
    end

    def level
      3
    end

    def indent
      0
    end

    def font_size
      20
    end

  end

  class SubsectionRenderer < SectionRenderer

    def section_title_renderer_class
      SubsectionTitleRenderer
    end

    def indent
      0
    end

  end

  class SubsectionTitleRenderer < SectionTitleRenderer

    def level
      4
    end

    def indent
      0
    end

    def font_size
      14
    end

  end

  class NoteRenderer < NodeRenderer

    def process
      @node.children.each do |node|
        klass = case node.name
        when 'simpara'
          SimparaRenderer
        end

        if klass
          @pdf.indent(20) do
            @pdf.formatted_text [ { text: 'NOTE', styles: [ :bold ], font: 'PT Sans' } ]
            klass.new(node, @pdf, @state).process
          end
        else
          notify_unhandled(node)
        end
      end
    end

  end

  class FigureRenderer < NodeRenderer

    def process
      handle_top_margin(10)

      # Title
      title = @node.children.find { |e| e.name == 'title' }
      text = title.children.find { |e| e.text? }.text

      # Image
      mediaobject = @node.children.find       { |e| e.name == 'mediaobject' }
      imageobject = mediaobject.children.find { |e| e.name == 'imageobject' }
      imagedata   = imageobject.children.find { |e| e.name == 'imagedata' }
      href = imagedata[:fileref]

      @pdf.indent(30, 30) do
        # FIXME do not prepend content/
        @pdf.image('static' + href, width: @pdf.bounds.width)
        @pdf.formatted_text([{
          text: "Figure #{@state.current_chapter}.#{@state.current_figure}: #{text}",
          styles: [ :italic ],
          font: 'Gentium Basic'
        }])
      end

      handle_bottom_margin(10)
    end

  end

  class SimparaRenderer < NodeRenderer

    def process
      handle_top_margin(10)

      text = @node.children.find { |e| e.text? }

      res = @node.children.map do |node|
        if node.text?
          next { text: node.text }
        end

        klass = case node.name
        when 'emphasis'
          EmphasisRenderer
        when 'literal'
          LiteralRenderer
        when 'ulink'
          UlinkRenderer
        when 'xref'
          XrefRenderer
        end

        if klass
          klass.new(node, @pdf, @state).process
        else
          notify_unhandled(node)
          {text: ''}
        end
      end

      @pdf.formatted_text(res)

      handle_bottom_margin(10)
    end

  end

  class ScreenRenderer < NodeRenderer

    def process
      handle_top_margin(10)

      @pdf.indent(20, 20) do
        res = @node.children.map do |node|
          if node.text?
            next { text: node.text.gsub(' ', Prawn::Text::NBSP) }
          end

          klass = case node.name
          when 'emphasis'
            EmphasisRenderer
          when 'literal'
            LiteralRenderer
          when 'ulink'
            UlinkRenderer
          when 'xref'
            XrefRenderer
          end

          if klass
            klass.new(node, @pdf, @state).process
          else
            notify_unhandled(node)
            {text: ''}
          end
        end

        @pdf.font('Cousine', size: 10) do
          @pdf.formatted_text(res)
        end
      end

      handle_bottom_margin(10)
    end

  end

  class ProgramListingRenderer < NodeRenderer

    def process
      handle_top_margin(10)

      @pdf.indent(20, 20) do
        res = @node.children.map do |node|
          if node.text?
            next { text: node.text.gsub(' ', Prawn::Text::NBSP) }
          end

          klass = case node.name
          when 'emphasis'
            EmphasisRenderer
          when 'literal'
            LiteralRenderer
          when 'ulink'
            UlinkRenderer
          when 'xref'
            XrefRenderer
          end

          if klass
            klass.new(node, @pdf, @state).process
          else
            notify_unhandled(node)
            {text: ''}
          end
        end

        @pdf.font('Cousine', size: 10) do
          @pdf.formatted_text(res)
        end
      end

      handle_bottom_margin(10)
    end

  end

  class EmphasisRenderer < NodeRenderer

    def process
      { text: @node.text, styles: [ :bold ] }
    end

  end

  class LiteralRenderer < NodeRenderer

    def process
      { text: @node.text, font: 'Cousine', size: 10 }
    end

  end

  class UlinkRenderer < NodeRenderer

    def process
      target = @node[:url]
      text   = @node.children.find { |e| e.text? }.text

      { text: text, link: target }
    end

  end

  class XrefRenderer < NodeRenderer

    def process
      { text: '(missing)' }
    end

  end

end
