defmodule TheGameWeb.Layouts do
  use TheGameWeb, :html

  embed_templates "layouts/*"

  # The logo: the TG shield mark (traced from the brand artwork) beside the serif wordmark.
  # One small fingerprinted SVG, cached forever and precached by the service worker, so it
  # costs a page nothing after the first visit. Source paths live in priv/logo_mark.path and
  # priv/wordmark.path.
  def wordmark(assigns) do
    ~H"""
    <img src={~p"/logo.svg"} alt="THE GAME" width="187" height="19" />
    """
  end
end
