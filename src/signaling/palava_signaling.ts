/*
 * decaffeinate suggestions:
 * DS001: Remove Babel/TypeScript constructor workaround
 * DS102: Remove unnecessary code created because of implicit returns
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
import { EventEmitter } from 'events';
import { Deferred } from '../internal/promise';
import { Signaling, SignalingPeer, Channel } from '../types';


/**
 * @module rtc.signaling
 */

/**
 * Signaling peer compatible with the framing of palava signaling
 * @class rtc.signaling.PalavaSignalingPeer
 * @extends rtc.signaling.SignalingPeer
 */
export class PalavaSignalingPeer extends EventEmitter implements SignalingPeer {

  channel: Channel;
  id: string;
  status: Record<string,any>;
  first: boolean;

  constructor(channel: Channel, id: string, status: Record<string,any>, first: boolean) {
      super();

    this.channel = channel;
    this.id = id;
    this.status = status;
    this.first = first;
    const recv_msg = (data: any) => {
      if (data.sender_id !== this.id) {
        // message is not for us
        return;
      }

      if ((data.event == null)) {
        this.send('error', "Invalid message");
        return;
      }

      return this.emit(data.event, data.data);
    };

    this.channel.on('message', recv_msg);

    this.on('peer_updated_status', status => {
      return this.emit('status_changed', status);
    });

    this.on('peer_left', () => {
      this.emit('closed');
      return this.channel.removeListener('message', recv_msg);
    });
  }


  send(event: string, data: any) {
    if (data == null) { data = {}; }
    return this.channel.send({
      event: 'send_to_peer',
      peer_id: this.id,
      data: {
        event,
        data
      }
    });
  }
};


/**
 * Signaling implementation compatible with the framing of palava signaling
 * @class rtc.signaling.PalavaSignaling
 * @extends rtc.signaling.Signaling
 */
export class PalavaSignaling extends EventEmitter implements Signaling<PalavaSignalingPeer> {

  channel: Channel;
  room: string;
  status: Record<string,any>;
  peers: Record<string,PalavaSignalingPeer>;
  joined: boolean;
  join_p?: Promise<void>;
  connect_p?: Promise<void>;

  constructor(channel: Channel, room: string, status: Record<string,any>) {
      super();

    this.channel = channel;
    this.room = room;
    this.status = status;
    this.peers = {};
    this.joined = false;

    const join_d = new Deferred<void>();
    this.join_p = join_d.promise;

    this.channel.on('closed', () => {
      return this.emit('closed');
    });

    this.channel.on('message', data => {
      let peer;
      if ((data.event == null)) {
        // invalid message
        return;
      }

      switch (data.event) {
        case 'joined_room':
          if ((data.peers == null) || (data.own_id == null)) {
            // invalid ...
            return;
          }

          for (let i in data.peers) {
            data = data.peers[i];
            peer = new PalavaSignalingPeer(this.channel, data.peer_id, data.status, false);
            this.peers[data.peer_id] = peer;
            this.emit('peer_joined', peer);
          }

          return join_d.resolve();

        case 'new_peer':
          if ((data.peer_id == null)) {
            // invalid ...
            return;
          }

          peer = new PalavaSignalingPeer(this.channel, data.peer_id, data.status, true);
          this.peers[data.peer] = peer;
          return this.emit('peer_joined', peer);
      }
    });
  }


  connect() {
    if ((this.connect_p == null)) {
      this.connect_p = this.channel.connect().then(() => {
        return this.channel.send({
          event: 'join_room',
          room_id: this.room,
          status
        });
      });
    }

    return this.connect_p;
  }


  setStatus(status: Record<string,any>) {
    return this.channel.send({
      event: 'update_status',
      status
    });
  }


  close() {
    return this.channel.close();
  }
};
