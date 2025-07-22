defmodule PhoenixApp.TimelineFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `PhoenixApp.Timeline` context.
  """

  @doc """
  Generate a user.
  """
  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        email: "some email"
      })
      |> PhoenixApp.Timeline.create_user()

    user
  end
end
