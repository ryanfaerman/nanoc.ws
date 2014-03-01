# encoding: utf-8

require 'asciidoctor'

module AsciidoctorPreview

  class Filter < ::Nanoc::Filter

    identifier :asciidoctor_preview

    def run(content, params={})
      ::Asciidoctor::Document.new(content).render(params)
    end

  end

end
