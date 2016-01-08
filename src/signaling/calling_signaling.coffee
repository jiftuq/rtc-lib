{EventEmitter} = require('events')
{Promise, Deferred} = require('../internal/promise')


class Calling extends EventEmitter

  constructor: (@channel) ->
    @next_tid = 0
    @answers = {}

    hello_d = new Deferred()
    @hello_p = hello_d.promise

    @channel.on 'message', (msg) =>
      switch msg.type
        when 'hello'
          @id = msg.id
          hello_d.resolve(msg.server)

        when 'answer'
          if not msg.tid?
            console.log('Missing transaction id in answer')
            return

          answer = @answers[msg.tid]
          delete @answers[msg.tid]

          if not answer?
            console.log('Answer without expecting it')
            return

          if answer.resolve?
            if msg.error?
              answer.reject(new Error(msg.error))
            else
              answer.resolve(msg.data)
          else
            if msg.error?
              answer(new Error(msg.error))
            else
              answer(undefined, msg.data)

        when 'invite_incoming'
          if not msg.handle? or not msg.user? or not msg.status? or not msg.data?
            console.log("Invalid message")
            return

          invitation = new CallingInInvitation(@, msg.handle, msg.user, msg.status, msg.data)
          @emit('invitation', invitation)


  connect: () ->
    @channel.connect().then () =>
      return @hello_p


  request: (msg, cb) ->
    msg.tid = @next_tid++

    @channel.send(msg)

    if cb?
      @answers[msg.tid] = cb
      return
    else
      defer = new Deferred()
      @answers[msg.tid] = defer
      return defer.promise


  subscribe: (nsid) ->
    # uses callback to avoid race conditions with promises
    return new Promise (resolve, reject) =>
      @request {
        type: 'ns_subscribe'
        namespace: nsid
      }, (err, data) =>
        if err?
          reject(err)
        else
          namespace = new CallingNamespace(@, nsid)

          for id, status of data.users
            namespace.addUser(id, status)

          for id, room of data.rooms
            namespace.addRoom(id, room.status, room.peers)

          resolve(namespace)


  register: (namespace) ->
    return @request({
      type: 'ns_user_register'
      namespace: namespace
    })


  unregister: (namespace) ->
    return @request({
      type: 'ns_user_unregister'
      namespace: namespace
    })


  room: (room) ->
    return new CallingRoom @, (status, cb) =>
      @request({
        type: 'room_join'
        room: room
        status: status
      }, cb)


  setStatus: (status) ->
    return @request({
      type: 'status'
      status: status
    })


class CallingNamespace extends EventEmitter

  constructor: (@calling, @id) ->
    @users = {}
    @rooms = {}

    message_handler = (msg) =>
      if msg.namespace != @id
        return

      switch msg.type
        when 'ns_user_add'
          if not msg.user? or not msg.status?
            console.log('Invalid message')
            return

          @addUser(msg.user, msg.status)

        when 'ns_user_update'
          if not msg.user? or not msg.status?
            console.log('Invalid message')
            return

          user = @users[msg.user]

          if not user?
            console.log('Unknown user in status change')
            return

          user.status = msg.status
          @emit('user_changed', user)
          @emit('user_status_changed', user, user.status)
          user.emit('status_changed', user.status)

        when 'ns_user_rm'
          if not msg.user?
            console.log('Invalid message')
            return

          user = @users[msg.user]

          if not user?
            console.log('Unknown user leaving')
            return

          delete @users[msg.user]

          @emit('user_changed', user)
          @emit('user_left', user)
          user.emit('left')

        when 'ns_room_add'
          if not msg.room? or not msg.status? or not msg.peers?
            console.log('Invalid message')
            return

          @addRoom(msg.room, msg.status, msg.peers)

        when 'ns_room_update'
          if not msg.room? or not msg.status?
            console.log('Invalid message')
            return

          room = @rooms[msg.room]

          if not room?
            console.log('Invalid room')
            return

          room.status = msg.status

          @emit('room_changed', room)
          @emit('room_status_changed', room, room.status)
          room.emit('status_changed', room.status)

        when 'ns_room_rm'
          if not msg.room?
            console.log('Invalid message')
            return

          room = @rooms[msg.room]

          if not room?
            console.log('Invalid room')
            return

          delete @rooms[msg.room]

          @emit('room_changed', room)
          @emit('room_closed')
          room.emit('closed')

        when 'ns_room_peer_add'
          if not msg.room? or not msg.user? or not msg.status? or not msg.pending?
            console.log('Invalid message')
            return

          room = @rooms[msg.room]

          if not room?
            console.log('Invalid room')
            return

          peer = room.addPeer(msg.user, msg.status, msg.pending)

          @emit('room_changed', room)
          @emit('room_peer_joined', room, peer)

        when 'ns_room_peer_update'
          if not msg.room? or not msg.user?
            console.log('Invalid message')
            return

          room = @rooms[msg.room]
          peer = room?.peers[msg.user]

          if not peer?
            console.log('Invalid peer')
            return

          if msg.status?
            peer.status = msg.status

            @emit('room_changed', room)
            @emit('room_peer_status_changed', room, peer, peer.status)
            peer.emit('status_changed', peer.status)

          if msg.pending? and msg.pending == false
            peer.pending = false
            peer.accepted_d.resolve()

            @emit('room_changed', room)
            @emit('peer_accepted', peer)
            peer.emit('accepted')

        when 'ns_room_peer_rm'
          if not msg.room? or not msg.user?
            console.log('Invalid message')
            return

          room = @rooms[msg.room]
          peer = room?.peers[msg.user]

          if not peer?
            console.log('Invalid peer')
            return

          delete @rooms[msg.room].peers[msg.user]

          @emit('room_changed', room)
          @emit('room_peer_left', room, peer)
          peer.emit('left')

    @calling.channel.on('message', message_handler)

    @on 'unsubscribed', () =>
      @calling.channel.removeListener('message', message_handler)


  addUser: (id, status) ->
    user = new CallingNamespaceUser(id, status)
    @users[id] = user
    @emit('user_changed', user)
    @emit('user_registered', user)
    return user


  addRoom: (id, status, peers) ->
    room = new CallingNamespaceRoom(id, status)

    for peer_id, peer of peers
      room.addPeer(peer_id, peer.status, peer.pending)

    @rooms[id] = room
    @emit('room_changed', room)
    @emit('room_registered', room)
    return room


  unsubscribe: () ->
    return new Promise (resolve, reject) =>
      @calling.request {
        type: 'ns_unsubscribe'
        namespace: @id
      }, (err) =>
        if err?
          reject(err)
        else
          for _, user of @users
            user.emit('left')

          @users = {}

          @emit('unsubscribed')

          resolve()


class CallingNamespaceUser extends EventEmitter

  constructor: (@id, @status, @pending) ->


class CallingNamespaceRoom extends EventEmitter

  constructor: (@id, @status) ->
    @peers = {}


  addPeer: (id, status, pending) ->
    peer = new CallingNamespaceRoomPeer(id, status, pending)
    @peers[id] = peer
    @emit('peer_joined', peer)
    return peer


class CallingNamespaceRoomPeer extends EventEmitter

  constructor: (@id, @status, @pending) ->
    @accepted_d = new Deferred()

    if not @pending
      @accepted_d.resolve()

    @on 'left', () =>
      @accepted_d.reject("Peer left")


  accepted: () ->
    return @accepted_d.promise


class CallingRoom extends EventEmitter

  constructor: (@calling, @connect_fun) ->
    @peer_status = {}
    @peers = {}

    message_handler = (msg) =>
      if msg.room != @id
        return

      switch msg.type
        when 'room_update'
          if not msg.status?
            console.log("Invalid message")
            return

          @status = msg.status
          @emit('status_changed', @status)

        when 'room_peer_add'
          if not msg.user? or not msg.pending? or not msg.status?
            console.log("Invalid message")
            return

          @addPeer(msg.user, msg.status, msg.pending, true)

        when 'room_peer_rm'
          console.log 'removing'
          if not msg.user?
            console.log("Invalid message")
            return

          peer = @peers[msg.user]

          if not peer?
            console.log("Unknown peer accepted")
            return

          delete @peers[msg.user]
          peer.accepted_d.reject("User left")
          console.log 'removed', @peers

          @emit('peer_left', peer)
          peer.emit('left')

        when 'room_peer_update'
          if not msg.user?
            console.log("Invalid message")
            return

          peer = @peers[msg.user]

          if not peer?
            console.log("Unknown peer accepted")
            return

          if msg.status?
            peer.status = msg.status

            @emit('peer_status_changed', peer, peer.status)
            peer.emit('status_changed', peer.status)

          if msg.pending? and msg.pending == false
            peer.pending = false
            peer.accepted_d.resolve()

            @emit('peer_accepted')
            peer.emit('accepted')


        when 'room_peer_from'
          if not msg.user? or not msg.event?
            console.log("Invalid message", msg)
            return

          peer = @peers[msg.user]

          if not peer?
            console.log("Unknown peer accepted")
            return

          @emit('peer_left')
          peer.emit(msg.event, msg.data)

    @calling.channel.on('message', message_handler)

    @on 'left', () =>
      @calling.channel.removeListener('message', message_handler)


  connect: () ->
    if not @connect_p?
      @connect_p = new Promise (resolve, reject) =>
        @connect_fun @peer_status, (err, res) =>
          if err?
            reject(err)
          else
            if not res.room? or not res.peers?
              reject(new Error("Invalid response from server"))
              return

            @id = res.room
            @status = res.status

            for user, data of res.peers
              @addPeer(user, data.status, data.pending, false)

            resolve()

    return @connect_p


  addPeer: (id, status, pending, first) ->
    peer = new CallingRoomPeer(@, id, status, pending, first)
    @peers[id] = peer
    @emit('peer_joined', peer)
    return peer


  leave: () ->
    return new Promise (resolve, reject) =>
      @calling.request {
        type: 'room_leave'
        room: @id
      }, (err) =>
        @emit('left')

        for _, peer of @peers
          peer.emit('left')
          peer.accepted_d.reject("You left the room")

        resolve()


  setStatus: (status) ->
    @peer_status = status

    if @connect_p?
      return @calling.request({
        type: 'room_peer_status'
        room: @id
        status: status
      })
    else
      return Promise.resolve()


  invite: (user, data={}) ->
    return new Promise (resolve, reject) =>
      @calling.request {
        type: 'invite_send'
        room: @id
        user: user.id
        data: data
      }, (err, res) =>
        if err?
          reject(err)
        else
          if not res.handle?
            reject(new Error("Invalid response"))
            return

          invitation = new CallingOutInvitation(@calling, res.handle)
          resolve(invitation)


  setRoomStatusSafe: (key, value, previous) ->
    return new Promise (resolve, reject) =>
      @calling.request {
        type: 'room_status'
        room: @id
        key: key
        value: value
        check: true
        previous: previous
      }, (err) =>
        if err
          reject(err)
          return

        @status[key] = value
        @emit('status_changed', @status)

        resolve()


  setRoomStatus: (key, value) ->
    return new Promise (resolve, reject) =>
      @calling.request {
        type: 'room_status'
        room: @id
        key: key
        value: value
      }, (err) =>
        if err
          reject(err)
          return

        @status[key] = value
        @emit('status_changed', @status)

        resolve()


  register: (namespace) ->
    return @calling.request({
      type: 'ns_room_register'
      namespace: namespace
      room: @id
    })


  unregister: (namespace, room) ->
    return @calling.request({
      type: 'ns_room_unregister'
      namespace: namespace
      room: @id
    })


class CallingRoomPeer extends EventEmitter

  constructor: (@room, @id, @status, @pending, @first) ->
    @accepted_d = new Deferred()

    if not @pending
      @accepted_d.resolve()

    return


  accepted: () ->
    return @accepted_d.promise


  send: (event, data) ->
    return @room.calling.request({
      type: 'room_peer_to'
      room: @room.id
      user: @id
      event: event
      data: data
    })


class CallingInInvitation extends EventEmitter

  constructor: (@calling, @handle, @user, @status, @data) ->
    @cancelled = false

    message_handler = (msg) =>
      if msg.handle != @handle
        return

      switch msg.type
        when 'invite_cancelled'
          @cancelled = true
          @emit('cancelled')
          @emit('handled')

    @calling.channel.on('message', message_handler)

    @on 'handled', () =>
      @calling.channel.removeListener('message', message_handler)

    return

  
  accept: () ->
    @emit('handled')
    return new CallingRoom @calling, (status, cb) =>
      @calling.request({
        type: 'ionvite_accept'
        handle: @handle
        status: status
      }, cb)


  deny: () ->
    @emit('handled')
    return @calling.request({
      type: 'deny'
      handle: @handle
    })


class CallingOutInvitation

  constructor: (@calling, @handle) ->
    @defer = new Deferred()

    message_handler = (msg) =>
      if msg.handle != @handle
        return

      switch msg.type
        when 'invite_response'
          if not msg.accepted?
            console.log("Invalid message")
            return

          @defer.resolve(msg.accepted)

    @calling.channel.on('message', message_handler)

    cleanup = () =>
      @calling.channel.removeListener('message', message_handler)

    @defer.promise.then(cleanup, cleanup)

    return


  response: () ->
    return @defer.promise


  cancel: () ->
    return @calling.request({
      type: 'invite_cancel'
      handle: @handle
    }).then () =>
      @defer.reject(new Error("Invitation cancelled"))
      return

module.exports = {
  Calling: Calling
  CallingNamespace: CallingNamespace
  CallingNamespaceUser: CallingNamespaceUser
  CallingNamespaceRoom: CallingNamespaceRoom
  CallingNamespaceRoomPeer: CallingNamespaceRoomPeer
  CallingRoom: CallingRoom
  CallingRoomPeer: CallingRoomPeer
  CallingInInvitation: CallingInInvitation
  CallingOutInvitation: CallingOutInvitation
}