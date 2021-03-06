import {EventEmitter} from 'events';

export type StreamTrackType = 'audio' | 'video';
export type StreamTrackSelection = StreamTrackType | 'both';

/**
 * @module rtc
 */
/**
 * A wrapper around an HTML5 MediaStream
 * @class rtc.Stream
 *
 * @constructor
 * @param {RTCDataStream} stream The native stream
 */
export class Stream extends EventEmitter {
  stream!: MediaStream;
  trackChangeCb: () => void;

  /**
   * Emitted when tracks are muted or unmuted. Only triggered when changes are
   * made through this objects mute functions.
   * @event mute_changed
   * @param {'audio' | 'video' | 'both'} type The type of tracks which changed
   * @param {Boolean} muted `true` if tracks were muted, `false` if they were unmuted
   */

  constructor(stream: MediaStream) {
    super();

    this.trackChangeCb = () => {
      this.emit("tracks_changed");

      this.emit('mute_changed', 'video', this.muted('video'));
      this.emit('mute_changed', 'audio', this.muted('audio'));
    };

    this.setStream(stream);
  }


  setStream(stream: MediaStream) {
    if(this.stream != null) {
      this.stream.removeEventListener("addtrack", this.trackChangeCb);
      this.stream.removeEventListener("removetrack", this.trackChangeCb);
    }

    this.stream = stream;

    this.emit("stream_changed", stream);

    this.trackChangeCb();

    this.stream.addEventListener("addtrack", this.trackChangeCb);
    this.stream.addEventListener("removetrack", this.trackChangeCb);
  }


  /**
   * Get the id of the stream. This is neither user defined nor human readable.
   * @method id
   * @return {String} The id of the underlying stream
   */
  id() {
    return this.stream.id;
  }


  /**
   * Checks whether the stream has any tracks of the given type
   * @method hasTracks
   * @param {'audio' | 'video' | 'both'} [type='both'] The type of track to check for
   * @return {Number} The amount of tracks of the given type
   */
  hasTracks(type: StreamTrackSelection) {
    return this.getTracks(type).length;
  }


  /**
   * Gets the tracks of the given type
   * @method getTracks
   * @param {'audio' | 'video' | 'both'} [type='both'] The type of tracks to get
   * @return {Array} An Array of the tracks
   */
  getTracks(type: StreamTrackSelection) {
    if (type === 'audio') {
      return this.stream.getAudioTracks();
    } else if (type === 'video') {
      return this.stream.getVideoTracks();
    } else if (type === 'both') {
      const video = this.stream.getVideoTracks();
      const vaudio = this.stream.getAudioTracks();
      return video.concat(vaudio);
    } else {
      throw new Error("Invalid stream part '" + type + "'");
    }
  }


  /**
   * Checks whether a type of track is muted. If there are no tracks of the
   * specified type they will be considered muted
   * @param {'audio' | 'video' | 'both'} [type='audio'] The type of tracks
   * @return {Boolean} Whether the tracks are muted
   */
  muted(type: StreamTrackSelection = 'audio'): boolean {
    const tracks = this.getTracks(type);

    if (tracks.length < 1) {
      return true;
    }

    const track = tracks[0]
    return track == null || !track.enabled;
  }


  /**
   * Mutes or unmutes tracks of the stream
   * @method mute
   * @param {Boolean} [muted=true] Mute on `true` and unmute on `false`
   * @param {'audio' | 'video' | 'both'} [type='audio'] The type of tracks to mute or unmute
   * @return {Boolean} Whether the tracks were muted or unmuted
   */
  mute(muted: boolean = true, type: StreamTrackSelection = 'audio') {
    const tracks = this.getTracks(type);

    if(tracks.length < 1) {
      return true;
    }

    for (let track of tracks) {
      track.enabled = !muted;
    }

    this.emit('mute_changed', type, muted);

    return muted;
  }


  /**
   * Toggles the mute state of tracks of the stream
   * @method toggleMute
   * @param {'audio' | 'video' | 'both'} [type='audio'] The type of tracks to mute or unmute
   * @return {Boolean} Whether the tracks were muted or unmuted
   */
  toggleMute(type: StreamTrackSelection = 'audio') {
    const tracks = this.getTracks(type);

    if (tracks.length < 1) {
      return true;
    }

    const muted = tracks[0].enabled;

    for (let track of tracks) {
      track.enabled = !muted;
    }

    this.emit('mute_changed', type, muted);

    return muted;
  }


  /**
   * Stops the stream
   * @method stop
   */
  stop() {
    this.stream.getTracks().forEach((track) => track.stop());
  }


  /**
   * Clones the stream. You can change both streams independently, for example
   * mute tracks. You will have to `stop()` both streams individually when you
   * are done.
   *
   * This is currently not supported in Firefox and expected to be implemented
   * in version 47. Use `Stream.canClone()` to check whether cloning is supported by
   * your browser.
   *
   * @method clone
   * @return {rtc.Stream} A clone of the stream
   */
  clone() {
    if (this.stream.clone == null) {
      throw new Error("Your browser does not support stream cloning. Firefox is expected to implement it in version 47.");
    }

    return new Stream(this.stream.clone());
  }


  /**
   * Checks whether cloning stream is supported by the browser. See `clone()`
   * for details
   * @static
   * @method canClone
   * @return {Boolean} `true` if cloning is supported, `false` otherwise
   */
  static canClone() {
    return MediaStream.prototype.clone != null;
  }


  /**
   * Creates a stream using `getUserMedia()`
   * @method createStream
   * @static
   * @param {Object} [config={audio: true, video: true}] The configuration to pass to `getUserMedia()`
   * @return {Promise -> rtc.Stream} Promise to the stream
   *
   * @example
   *     var stream = rtc.Stream.createStream({audio: true, video: false});
   *     rtc.MediaDomElement($('video'), stream);
   */
  static createStream(config: MediaStreamConstraints = {audio: true, video: true}) {
    // TODO
    return navigator.mediaDevices.getUserMedia(config).then(native_stream => new Stream(native_stream));
  }
};

