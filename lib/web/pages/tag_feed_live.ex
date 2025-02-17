defmodule Bonfire.Tag.Web.TagFeedLive do
  use Bonfire.UI.Common.Web, :surface_live_view

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(%{"id" => id} = _params, _session, socket) do
    # debug(id, "id")

    with {:ok, tag} <- Bonfire.Tag.get(id) do
      ok_assigns(
        socket,
        tag,
        e(tag, :profile, :name, nil) || e(tag, :post_content, :name, nil) || e(tag, :name, nil) ||
          e(tag, :named, :name, nil) || l("Tag")
      )
    else
      {:error, :not_found} -> mount(%{"hashtag" => id}, nil, socket)
    end
  end

  def mount(%{"hashtag" => hashtag}, _session, socket) do
    debug(hashtag, "hashtag")

    cond do
      not extension_enabled?(:bonfire_tag, socket) ->
        {:ok,
         socket
         |> redirect_to("/search?s=#{hashtag}")}

      is_uid?(hashtag) ->
        mount(%{"id" => hashtag}, nil, socket)

      true ->
        with {:ok, tag} <-
               Bonfire.Tag.one([name: hashtag], pointable: Bonfire.Data.Identity.Named) do
          #  |> repo().maybe_preload(:named) do
          ok_assigns(socket, tag, "#{e(tag, :name, hashtag)}")
        end
    end
  end

  def ok_assigns(socket, tag, name) do
    {:ok,
     assign(
       socket,
       page: "tag",
       back: true,
       page_title: "#" <> name,
       object_type: nil,
       feed: [],
       hide_tabs: true,
       selected_tab: :timeline,
       #  smart_input_opts: %{text_suggestion: name}, # TODO: new post with tag button instead
       tag: tag,
       canonical_url: canonical_url(tag),
       name: name,
       nav_items: Bonfire.Common.ExtensionModule.default_nav(),
       sidebar_widgets: [
         users: [
           secondary: [
             {Bonfire.Tag.Web.WidgetTagsLive, []}
           ]
         ]
       ]
     )}
  end

  def tab(selected_tab) do
    case maybe_to_atom(selected_tab) do
      tab when is_atom(tab) -> tab
      _ -> :timeline
    end

    # |> debug
  end

  def handle_params(%{"tab" => tab} = _params, _url, socket)
      when tab in ["posts", "timeline"] do
    # FIXME!
    {:noreply,
     socket
     |> assign(
       Bonfire.Social.Feeds.LiveHandler.feed_default_assigns(
         {"feed_profile_timeline",
          Bonfire.Tag.Tagged.q_with_tag(uid(e(socket.assigns, :tag, nil)))},
         socket
       )
       |> debug("tag_feed_assigns_maybe_async")
     )
     |> assign(
       selected_tab: tab(tab)
       #  page_title: e(socket.assigns, :name, nil),
       #  page_title: "#{e(socket.assigns, :name, nil)} #{tab(tab)}")
       #  page_header_icon: "mingcute:hashtag-fill"
     )}
  end

  def handle_params(params, _url, socket) do
    # default tab
    handle_params(
      Map.merge(params || %{}, %{"tab" => "timeline"}),
      nil,
      socket
    )
  end
end
