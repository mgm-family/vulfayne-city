// src(発信者のサーバーID) -> YT.Playerインスタンス
let players = {};

// YouTube IFrame APIの読み込み完了前にcreateが来た場合に備えるキュー
let pendingCreates = [];
let apiReady = false;

// YouTube IFrame APIが読み込まれると自動で呼ばれます(YouTube側の仕様)
function onYouTubeIframeAPIReady() {
    apiReady = true;
    pendingCreates.forEach((c) => createPlayer(c.src, c.videoId));
    pendingCreates = [];
}

function createPlayer(src, videoId) {
    if (!apiReady) {
        pendingCreates.push({ src, videoId });
        return;
    }

    destroyPlayer(src);

    const container = document.createElement('div');
    container.className = 'yt-container';
    container.id = `yt-player-${src}`;
    document.getElementById('players').appendChild(container);

    players[src] = new YT.Player(container.id, {
        height: '2',
        width: '2',
        videoId: videoId,
        playerVars: {
            autoplay: 1,
            controls: 0,
            disablekb: 1,
            fs: 0,
            modestbranding: 1,
            loop: 1,
            playlist: videoId // loop:1を単一動画で機能させるために必要
        },
        events: {
            onReady: (e) => {
                e.target.setVolume(0);
                e.target.playVideo();
            }
        }
    });
}

function destroyPlayer(src) {
    if (players[src]) {
        try {
            players[src].destroy();
        } catch (e) {
            // 既に破棄済みの場合は無視します
        }
        delete players[src];
    }

    const el = document.getElementById(`yt-player-${src}`);
    if (el) el.remove();
}

function setVolume(src, volume) {
    const player = players[src];
    if (!player || typeof player.setVolume !== 'function') return;

    const v = Math.max(0, Math.min(100, volume));
    player.setVolume(v);

    if (v <= 0) {
        player.mute();
    } else {
        player.unMute();
    }
}

// Lua側からのSendNUIMessageをここで受け取ります
window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || !data.action) return;

    switch (data.action) {
        case 'create':
            createPlayer(data.src, data.videoId);
            break;
        case 'setVolume':
            setVolume(data.src, data.volume);
            break;
        case 'destroy':
            destroyPlayer(data.src);
            break;
    }
});
