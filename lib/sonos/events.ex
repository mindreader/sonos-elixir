defmodule Sonos.Events do
  import SweetXml

  # if avtransporturi starts with 'x-rincon:', that may signal that it is the coordinator


  def group_rendering_control(doc) do
    doc |> xpath(~x"//e:propertyset"l,
      group_volume: ~x"./e:property/GroupVolume/text()"i,
      group_mute: ~x"./e:property/GroupMute/text()"i,
      group_volume_changeable: ~x"./e:property/GroupVolumeChangeable/text()"i
    )
  end

  def content_directory(doc) do
    doc |> xpath(~x"//e:propertyset"l,
      system_update_id: ~x"./e:property/SystemUpdateID/text()"s,
      container_update_ids: ~x"./e:property/ContainerUpdateIDs/text()"s,
      share_index_in_progress: ~x"./e:property/ShareIndexInProgress/text()"s,
      favorites_update_id: ~x"./e:property/FavoritesUpdateID/text()"s,
      radio_favorites_update_id: ~x"./e:property/FavoritePresetsUpdateID/text()"s,
      radio_location_update_id: ~x"./e:property/RadioFavoritesUpdateID/text()"s,
      saved_queues_update_id: ~x"./e:property/SavedQueuesUpdateID/text()"s,
      shared_list_update_id: ~x"./e:property/ShareListUpdateID/text()"s
    )
  end

  def zone_group_state(doc) do
    doc
    |> xpath(~x"//e:propertyset/e:property/ZoneGroupState/text()"S)
    |> xpath(~x"//ZoneGroupState/ZoneGroups/ZoneGroup"l) |> Enum.map(fn zg ->
      zg |> xpath(~x"./ZoneGroupMember"l,
        uuid: ~x"./@UUID"s,
        location: ~x"./@Location"s,
        zone_name: ~x"./@ZoneName"s,
        icon: ~x"./@Icon"s,
        configuration: ~x"./@Configuration"i,
        software_version: ~x"./@SoftwareVersion"s,
        sw_gen: ~x"./@SWGen"i,
        idle_state: ~x"./@IdleState"i,
        more_info: ~x"./@MoreInfo"s
      )
    end)
  end

  def last_change(doc) do
    try do
      doc
      |> xpath(~x"//e:propertyset/e:property/LastChange/text()")
      |> xpath(~x"//Event/InstanceID",
        transport_state: ~x"./TransportState/@val"s,
        play_mode: ~x"./CurrentPlayMode/@val"s,
        crossfade_mode: ~x"./CurrentCrossfadeMode/@val"s,
        number_of_tracks: ~x"./NumberOfTracks/@val"s,
        current_track: ~x"./CurrentTrack/@val"s,
        current_section: ~x"./CurrentSection/@val"s,
        current_track_uri: ~x"./CurrentTrackURI/@val"s,
        current_track_duration: ~x"./CurrentTrackDuration/@val"s,
        current_track_metadata:
          ~x"./CurrentTrackMetaData/@val"s
          |> transform_by(&didl_lite/1),
        next_track_uri: ~x"./r:NextTrackURI/@val"s,
        next_track_metadata: ~x"./r:NextTrackMetaData/@val"s,
        enqueued_transport_uri: ~x"./r:EnqueuedTransportURI/@val"s,
        enqueued_transport_uri_metadata:
          ~x"./r:EnqueuedTransportURIMetaData/@val"s
          |> transform_by(&didl_lite/1),
        playback_storage_medium: ~x"./PlaybackStorageMedium/@val"s,
        av_transport_uri: ~x"./AVTransportURI/@val"s,
        av_transport_uri_metadata:
          ~x"./AVTransportURIMetaData/@val"s
          |> transform_by(&didl_lite/1),
        current_transport_actions:
          ~x"./CurrentTransportActions/@val"s
          |> transform_by(fn str -> str |> String.downcase() |> String.split(", ") end),
        current_valid_play_modes:
          ~x"./r:CurrentValidPlayModes/@val"s
          |> transform_by(fn str -> str |> String.downcase() |> String.split(", ") end),
        muse_sessions: ~x"./r:MuseSessions/@val"s,
        direct_control_client_id: ~x"./r:DirectControlClientID/@val"s,
        direct_control_is_suspended: ~x"./r:DirectControlIsSuspended/@val"s,
        direct_control_account_id: ~x"./r:DirectControlAccountID/@val"s,
        direct_control_account_id: ~x"./r:DirectControlAccountID/@val"s,
        transport_status: ~x"./TransportStatus/@val"s,
        sleep_timer_generation: ~x"./r:SleepTimerGeneration/@val"s,
        alarm_running: ~x"./r:AlarmRunning/@val"s,
        snooze_running: ~x"./r:SnoozeRunning/@val"s,
        restart_pending: ~x"./r:RestartPending/@val"s
        )
      catch
        :exit, e -> {:error, e}
    end
  end

  def didl_lite(doc) do
    doc
    |> xpath(~x"//DIDL-Lite/item",
      res: ~x"./res/text()"s,
      desc: ~x"./desc/text()"s,
      title: ~x"./dc:title/text()"s
    )
    |> Map.put(:doc, doc)
  end
end
