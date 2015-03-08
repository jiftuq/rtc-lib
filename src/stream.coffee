class Stream

  AUDIO: 'audio'
  VIDEO: 'video'
  BOTH: 'both'


  constructor: (@stream) ->


  setLabel: (label) ->
    @stream.label = label


  label: () ->
    return @stream.label


  hasAudio: () ->
    return stream.getAudioTracks().length > 0


  hasVideo: () ->
    return stream.getVideoTracks().length > 0


  getTracks: (type) ->
    type = type.toLowerCase()

    if type == 'audio'
      return @stream_p.then (stream) ->
        return stream.getAudioTracks()
    else if type == 'video'
      return @stream_p.then (stream) ->
        return stream.getVideoTracks()
    else if type == 'both'
      return @stream_p.then (stream) ->
        video = stream.getVideoTracks()
        vaudio = stream.getAudioTracks()
        return video.concat(audio)
    else
      throw new Error("Invalid stream part '" + type + "'")


  mute: (muted=true, type='audio') ->
    for track in getTracks(type)
      track.enabled = not muted

    return muted


  toggleMute: (type='audio') ->
    tracks = getTracks(type)

    muted = not tracks[0]?.enabled

    for track in tracks
      track.enabled = not muted

    return muted


  stop: () ->
    stream.stop()


exports.Stream = Stream
