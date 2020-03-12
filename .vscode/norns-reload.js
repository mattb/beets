const WebSocket = require('ws');

const ws = new WebSocket('ws://norns.local:5555/', ['bus.sp.nanomsg.org']);

ws.on('open', function open() {
    ws.send('norns.script.load()\n');
});

ws.on('message', (d) => {
    if (d.trim() === '<ok>') {
        ws.close();
        console.log('-- Updated Norns --');
    }
});
