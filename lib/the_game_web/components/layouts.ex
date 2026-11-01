defmodule TheGameWeb.Layouts do
  use TheGameWeb, :html

  embed_templates "layouts/*"

  # The wordmark is the Anton display face converted to a single SVG path at build time:
  # zero font downloads, crisp at any size, ~1.1 KB inline.
  @path_file Path.join(:code.priv_dir(:the_game) |> to_string(), "wordmark.path")
  @external_resource @path_file
  @wordmark_path File.read!(@path_file)

  def wordmark(assigns) do
    assigns = assign(assigns, :d, @wordmark_path)

    ~H"""
    <svg viewBox="0 12 409 90" role="img" aria-hidden="true"><path d={@d} /></svg>
    """
  end
end
