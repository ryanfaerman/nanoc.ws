# encoding: utf-8

def asciidoctor_demote_headers(content)
  # FIXME this is awful
  content.gsub(/(=+) /m, '=\1 ')
end
