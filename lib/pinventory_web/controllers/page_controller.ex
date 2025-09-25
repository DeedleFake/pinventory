defmodule PinventoryWeb.PageController do
  use PinventoryWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
