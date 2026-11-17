module Seek
  module Renderers
    class MarkdownRenderer < IframeRenderer
      def can_render?
        blob.is_markdown?
      end

      def display_format
        'markdown'
      end

      def render_standalone
        "<div class=\"markdown-body\">#{Seek::Markdown.render(blob.read)}</div>"
      end

      def layout
        'blob'
      end

      # Content-Security-Policy for the rendered view.
      # This does not set default-src since the img-src needs to be blank to allow images from ourside the iframe to be able to be rendered.
      # Specifically, the badges that many github repos use to indicate eg versions of tools used do not render with img-src: self.
      # The default for this in blob_renderer.rb is default-src: self, which propagates to the img-src. So we can't set that.
      # The script-src is set to self to protect from cross site scripting.
      def content_security_policy
        "script-src 'self';"
      end
    end
  end
end
