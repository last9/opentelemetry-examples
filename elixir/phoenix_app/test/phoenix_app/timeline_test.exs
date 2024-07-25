defmodule PhoenixApp.TimelineTest do
  use PhoenixApp.DataCase

  alias PhoenixApp.Timeline

  describe "users" do
    alias PhoenixApp.Timeline.User

    import PhoenixApp.TimelineFixtures

    @invalid_attrs %{email: nil}

    test "list_users/0 returns all users" do
      user = user_fixture()
      assert Timeline.list_users() == [user]
    end

    test "get_user!/1 returns the user with given id" do
      user = user_fixture()
      assert Timeline.get_user!(user.id) == user
    end

    test "create_user/1 with valid data creates a user" do
      valid_attrs = %{email: "some email"}

      assert {:ok, %User{} = user} = Timeline.create_user(valid_attrs)
      assert user.email == "some email"
    end

    test "create_user/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Timeline.create_user(@invalid_attrs)
    end

    test "update_user/2 with valid data updates the user" do
      user = user_fixture()
      update_attrs = %{email: "some updated email"}

      assert {:ok, %User{} = user} = Timeline.update_user(user, update_attrs)
      assert user.email == "some updated email"
    end

    test "update_user/2 with invalid data returns error changeset" do
      user = user_fixture()
      assert {:error, %Ecto.Changeset{}} = Timeline.update_user(user, @invalid_attrs)
      assert user == Timeline.get_user!(user.id)
    end

    test "delete_user/1 deletes the user" do
      user = user_fixture()
      assert {:ok, %User{}} = Timeline.delete_user(user)
      assert_raise Ecto.NoResultsError, fn -> Timeline.get_user!(user.id) end
    end

    test "change_user/1 returns a user changeset" do
      user = user_fixture()
      assert %Ecto.Changeset{} = Timeline.change_user(user)
    end
  end
end
