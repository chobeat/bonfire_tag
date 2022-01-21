# Bonfire.Common.Config.require_extension_config!(:bonfire_tag)
defmodule Bonfire.Tag.Tags do

  use Arrows
  import Bonfire.Common.Config, only: [repo: 0]
  alias Bonfire.Common.{Types, Utils}

  alias Pointers.Pointer # warning: do not move after we alias Pointers
  alias Bonfire.Common.{Pointers, Utils} # warning: do not move before we alias Pointer
  alias Bonfire.Me.Characters
  alias Bonfire.Tag.{AutoComplete, Queries, TextContent.Process}

  require Logger


  @doc """
  Retrieves a single tag by arbitrary filters.
  Used by:
  * GraphQL Item queries
  * ActivityPub integration
  * Various parts of the codebase that need to query for tags (inc. tests)
  """
  def one(filters), do: repo().single(Queries.query(filters))

  @doc """
  Retrieves a list of tags by arbitrary filters.
  Used by:
  * Various parts of the codebase that need to query for tags (inc. tests)
  """
  def many(filters \\ []), do: {:ok, repo().many(Queries.query(filters))}


  def get(id) do
    if Bonfire.Common.Utils.is_ulid?(id),
      do: one(id: id),
      # TODO: lookup Peered with canonical_uri if id is a URL
      else: Utils.maybe_apply(Characters, :by_username, id) <~> one(username: id)
  end

  def find(id) do
    if Bonfire.Common.Utils.is_ulid?(id),
      do: one(id: id),
      # TODO: lookup Peered with canonical_uri if id is a URL
      else: many(autocomplete: id)
  end

  # def many(filters \\ []), do: {:ok, repo().many(Queries.query(Tag, filters))}

  def prefix("Community"), do: "&"
  def prefix("User"), do: "@"
  def prefix(_), do: "+"

  def maybe_find_tag(user \\ nil, id_or_username_or_url) when is_binary(id_or_username_or_url) do
    Logger.debug("Tags.maybe_find_tag: #{id_or_username_or_url}")
    get(id_or_username_or_url) <~> # check if tag already exists
    (if Bonfire.Common.Utils.is_ulid?(id_or_username_or_url) do
      Logger.debug("Tags.maybe_find_tag: try by ID")
      Pointers.one(id_or_username_or_url, current_user: user, skip_boundary_check: true)
    else
      # if Bonfire.Common.Extend.extension_enabled?(Bonfire.Federate.ActivityPub) do
      Logger.info("Tags.maybe_find_tag: try get_by_url_ap_id_or_username")
      with {:ok, federated_object_or_character} <- Bonfire.Federate.ActivityPub.Utils.get_by_url_ap_id_or_username(id_or_username_or_url) do
        Logger.debug("Tags: federated_object_or_character: #{inspect federated_object_or_character}")
        {:ok, federated_object_or_character}
      end
      # else
      #   {:error, "no such tag"}
      # end
    end)
  end

  @doc """
  Search / autocomplete for tags by name
  """
  def maybe_find_tags(_user \\ nil, id_or_username_or_url)
  when is_binary(id_or_username_or_url) do
    Logger.info("Tags.maybe_find_tag: #{id_or_username_or_url}")
    find(id_or_username_or_url) <~> # check if tag already exists
    {:ok, [maybe_find_tag(id_or_username_or_url)]}
  end

  @doc """
  Lookup a signle for a tag by its name/username
  """
  def maybe_lookup_tag(id_or_username_or_url, _prefix \\ "@")
  when is_binary(id_or_username_or_url), do: maybe_find_tag(id_or_username_or_url)


  def maybe_taxonomy_tag(user, id) do
    if Bonfire.Common.Extend.extension_enabled?(Bonfire.TaxonomySeeder.TaxonomyTags) do
      Bonfire.TaxonomySeeder.TaxonomyTags.maybe_make_category(user, id)
    end
  end

  ### Functions for tagging things ###

  @doc """
  Maybe tag something
  """
  def maybe_tag(user, thing, tags \\ nil, boost_category_mentions? \\ true)
  # def maybe_tag(user, thing, %{tags: tag_string}) when is_binary(tag_string) do
  #   tag_strings = Bonfire.Tag.Autocomplete.tags_split(tag_string)
  #   tag_something(user, thing, tag_strings)
  # end
  def maybe_tag(user, thing, %{tags: tags}, boost_category_mentions?), do: maybe_tag(user, thing, tags, boost_category_mentions?)
  def maybe_tag(user, thing, %{tag: tag}, boost_category_mentions?), do: maybe_tag(user, thing, tag, boost_category_mentions?)
  def maybe_tag(user, thing, tags, boost_category_mentions?) when is_list(tags), do: tag_something(user, thing, tags, boost_category_mentions?)
  def maybe_tag(user, thing, %{__struct__: _} = tag, boost_category_mentions?), do: tag_something(user, thing, tag, boost_category_mentions?)
  def maybe_tag(user, thing, text, boost_category_mentions?) when is_binary(text) do
    tags = if text != "", do: Autocomplete.find_all_tags(text) # TODO, switch to TextContent.Process?
    if is_map(tags) or (is_list(tags) and tags != []) do
      maybe_tag(user, thing, tags, boost_category_mentions?)
    else
      Logger.info("Bonfire.Tag - no matches in '#{text}'")
      {:ok, thing}
    end
  end
  def maybe_tag(user, obj, _, boost_category_mentions?), # otherwise maybe we have tagnames inline in the text of the object?
    do: maybe_tag(user, obj, Process.object_text_content(obj), boost_category_mentions?)
  # def maybe_tag(_user, thing, _maybe_tags, boost_category_mentions?) do
  #   #IO.inspect(maybe_tags: maybe_tags)
  #   {:ok, thing}
  # end


  @doc """
  tag existing thing with one or multiple Tags, Pointers, or anything that can be made into a tag
  """
  # def tag_something(user, thing, tags) when is_struct(thing) do
  #   with {:ok, tagged} <- do_tag_thing(user, thing, tags) do
  #     {:ok, Map.put(thing, :tags, Map.get(tagged, :tags, []))}
  #   end
  # end
  def tag_something(user, thing, tags, boost_category_mentions? \\ false) do
    with {:ok, thing} <- do_tag_thing(user, thing, tags) do
      if boost_category_mentions?
      and Bonfire.Common.Utils.module_enabled?(Bonfire.Classify.Categories)
      and Bonfire.Common.Utils.module_enabled?(Bonfire.Social.Boosts) do
        Logger.debug("Bonfire.Tag: boost mentions to the category's feed")
        thing.tags
        |> repo().maybe_preload([:category, :character])
        |> Enum.reject(&(is_nil(&1.category) or is_nil(&1.character)))
        |> Enum.each(&Bonfire.Social.Boosts.boost(&1, thing))
      end
      {:ok, thing}
    end
  end

  #doc """ Add tag(s) to a pointable thing. Will replace any existing tags. """
  defp do_tag_thing(user, thing, tags) when is_list(tags) do
    pointer = thing_to_pointer(thing)
    tags = Enum.map(tags, &tag_preprocess(user, &1)) |> Enum.reject(&is_nil/1)
    # IO.inspect(do_tag_thing: tags)
    with {:ok, tagged} <- thing_tags_save(pointer, tags) do
       {:ok, (if is_map(thing), do: thing, else: pointer) |> Map.merge(%{tags: tags})}
    end
    # Bonfire.Repo.maybe_preload(thing, :tags)
  end
  defp do_tag_thing(user, thing, tag), do: do_tag_thing(user, thing, [tag])

  #doc """ Prepare a tag to be used, by loading or even creating it """
  defp tag_preprocess(_user, %{__struct__: _} = tag), do: tag
  defp tag_preprocess(_, tag) when is_nil(tag) or tag == "", do: nil
  defp tag_preprocess(_user, {:error, e}) do
    Logger.warn("Tags: invalid tag: #{inspect e}")
    nil
  end

  defp tag_preprocess(user, {_at_mention, tag}), do: tag_preprocess(user, tag)
  defp tag_preprocess(user, "@" <> tag), do: tag_preprocess(user, tag)
  defp tag_preprocess(user, "+" <> tag), do: tag_preprocess(user, tag)
  defp tag_preprocess(user, "&" <> tag), do: tag_preprocess(user, tag)
  defp tag_preprocess(_user, tag) do
    Logger.error("Tags.tag_preprocess: didn't recognise this as a tag: #{inspect tag} ")
    nil
  end

  def tag_ids(tags) when is_list(tags), do: Enum.map(tags, &tag_ids(&1))
  def tag_ids({_at_mention, %{id: tag_id}}), do: tag_id
  def tag_ids(%{id: tag_id}), do: tag_id

  defp thing_tags_save(%{} = thing, [_|_] = tags) do
    tags
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&(&1.id))
    # |> Utils.debug("tags")
    |> Bonfire.Tag.thing_tags_changeset(thing, tags)
    # |> Utils.debug("changeset")
    |> repo().transact_with(fn -> repo().update(..., on_conflict: :nothing) end)
  end
  defp thing_tags_save(thing, _tags), do: {:ok, thing}

  defp thing_to_pointer(%{}=thing), do: Pointers.maybe_forge(thing)
  defp thing_to_pointer(pointer_id) when is_binary(pointer_id),
    do: Pointers.one(id: pointer_id, skip_boundary_check: true)

  def indexing_object_format(object) do
    # IO.inspect(indexing_object_format: object)
    %{
      "id"=> object.id,
      "name"=> object.profile.name,
      "summary"=> object.profile.summary,
      "prefix"=> object.prefix,
      "facet"=> object.facet
      # TODO: add url/username
    }
  end

  def indexing_object_format_name(object), do: object.profile.name

end
