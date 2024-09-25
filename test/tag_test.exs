defmodule Bonfire.Tag.TagTest do
  use Bonfire.Tag.DataCase, async: true
  use Bonfire.Common.Utils
  import Bonfire.Posts.Fake
  alias Bonfire.Posts
  alias Bonfire.Tag
  alias Needle.Tables
  alias Ecto.Changeset
  alias Bonfire.Me.Fake
  def repo, do: Config.repo()

  test "tag creation" do
    assert {:error, _} = Tag.get("test")
    {:ok, tag_1} = Tag.get_or_create_hashtag("test")
    assert tag_1.named.name == "test"

    {:ok, tag_2} = Tag.get_or_create_hashtag("test")
    assert tag_1.id == tag_2.id
  end
end
