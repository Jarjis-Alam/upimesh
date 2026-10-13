/**
 * UPI OFFLINE MESH — Cinematic Audio Engine
 * Synchronized background track + precision synthesized SFX.
 * Auto-synchronizes with animation seek(t).
 */

class TeaserAudioEngine {
  constructor() {
    this.ctx = null;
    this.masterGain = null;
    this.isMuted = false;
    this.audioElement = new Audio();
    this.audioElement.src = 'assets/audio/soundtrack.mp3';
    this.audioElement.preload = 'auto';
    this.hasUserInteracted = false;
    this.audioLoaded = false;

    this.audioElement.addEventListener('canplaythrough', () => {
      this.audioLoaded = true;
    });

    this.audioElement.addEventListener('error', () => {
      console.log('Audio file not found or blocked, falling back to pure Web Audio synthesis.');
      this.audioLoaded = false;
    });
  }

  init() {
    if (this.ctx) return;
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    if (!AudioContextClass) return;

    this.ctx = new AudioContextClass();
    this.masterGain = this.ctx.createGain();
    this.masterGain.gain.setValueAtTime(this.isMuted ? 0 : 0.7, this.ctx.currentTime);
    this.masterGain.connect(this.ctx.destination);
  }

  toggleMute() {
    this.init();
    if (this.ctx && this.ctx.state === 'suspended') {
      this.ctx.resume();
    }
    this.isMuted = !this.isMuted;
    this.hasUserInteracted = true;

    if (this.audioElement) {
      this.audioElement.muted = this.isMuted;
      if (!this.isMuted && this.isPlayingState) {
        this.audioElement.play().catch(() => {});
      }
    }

    if (this.masterGain) {
      const now = this.ctx.currentTime;
      this.masterGain.gain.cancelScheduledValues(now);
      this.masterGain.gain.setTargetAtTime(this.isMuted ? 0 : 0.7, now, 0.05);
    }
    return !this.isMuted;
  }

  syncPlayback(isPlaying, currentTime) {
    this.isPlayingState = isPlaying;
    if (!this.hasUserInteracted) return;

    if (this.audioLoaded && !this.isMuted) {
      if (isPlaying) {
        if (Math.abs(this.audioElement.currentTime - currentTime) > 0.3) {
          this.audioElement.currentTime = currentTime;
        }
        this.audioElement.play().catch(() => {});
      } else {
        this.audioElement.pause();
      }
    }
  }

  seek(t) {
    if (this.audioLoaded) {
      this.audioElement.currentTime = t;
    }
  }

  // Precise SFX cues matching the 24s sequence
  onTimeUpdate(t, prevT) {
    if (this.isMuted || !this.ctx) return;
    if (this.ctx.state === 'suspended') return;

    // t = 1.2s: Disconnect tone
    if (prevT < 1.2 && t >= 1.2) {
      this.playDisconnectGlitch();
    }
    // t = 3.6s: Packet Creation Ping
    if (prevT < 3.6 && t >= 3.6) {
      this.playPacketCreatedPing();
    }
    // t = 8.4s: Mesh Connection Broken tone
    if (prevT < 8.4 && t >= 8.4) {
      this.playWarningTone();
    }
    // t = 9.2s: Reroute spark
    if (prevT < 9.2 && t >= 9.2) {
      this.playRerouteSpark();
    }
    // t = 10.2s, 11.4s: Hop pings
    if (prevT < 10.2 && t >= 10.2) {
      this.playMeshHopPing(440);
    }
    if (prevT < 11.4 && t >= 11.4) {
      this.playMeshHopPing(554.37);
    }
    // t = 13.5s: Cryptographic Lock
    if (prevT < 13.5 && t >= 13.5) {
      this.playCryptoLock();
    }
    // t = 17.5s: Ledger Sync resolution
    if (prevT < 17.5 && t >= 17.5) {
      this.playLedgerSyncChime();
    }
    // t = 20.0s: Final cinematic reveal 808 sub-drop
    if (prevT < 20.0 && t >= 20.0) {
      this.playRevealSubDrop();
    }
  }

  playDisconnectGlitch() {
    const now = this.ctx.currentTime;
    const bufferSize = this.ctx.sampleRate * 0.15;
    const buffer = this.ctx.createBuffer(1, bufferSize, this.ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < bufferSize; i++) {
      data[i] = (Math.random() * 2 - 1) * Math.exp(-i / (bufferSize * 0.3));
    }
    const noise = this.ctx.createBufferSource();
    noise.buffer = buffer;

    const filter = this.ctx.createBiquadFilter();
    filter.type = 'bandpass';
    filter.frequency.setValueAtTime(650, now);
    filter.Q.setValueAtTime(4, now);

    const gain = this.ctx.createGain();
    gain.gain.setValueAtTime(0.25, now);
    gain.gain.exponentialRampToValueAtTime(0.001, now + 0.18);

    noise.connect(filter);
    filter.connect(gain);
    gain.connect(this.masterGain);

    noise.start(now);
  }

  playPacketCreatedPing() {
    const now = this.ctx.currentTime;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();

    osc.type = 'sine';
    osc.frequency.setValueAtTime(587.33, now); // D5
    osc.frequency.exponentialRampToValueAtTime(880, now + 0.1);

    gain.gain.setValueAtTime(0.2, now);
    gain.gain.exponentialRampToValueAtTime(0.001, now + 0.35);

    osc.connect(gain);
    gain.connect(this.masterGain);

    osc.start(now);
    osc.stop(now + 0.35);
  }

  playWarningTone() {
    const now = this.ctx.currentTime;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();

    osc.type = 'sawtooth';
    osc.frequency.setValueAtTime(220, now);
    osc.frequency.linearRampToValueAtTime(160, now + 0.15);

    gain.gain.setValueAtTime(0.18, now);
    gain.gain.exponentialRampToValueAtTime(0.001, now + 0.22);

    osc.connect(gain);
    gain.connect(this.masterGain);

    osc.start(now);
    osc.stop(now + 0.22);
  }

  playRerouteSpark() {
    const now = this.ctx.currentTime;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();

    osc.type = 'triangle';
    osc.frequency.setValueAtTime(330, now);
    osc.frequency.exponentialRampToValueAtTime(660, now + 0.12);

    gain.gain.setValueAtTime(0.2, now);
    gain.gain.exponentialRampToValueAtTime(0.001, now + 0.25);

    osc.connect(gain);
    gain.connect(this.masterGain);

    osc.start(now);
    osc.stop(now + 0.25);
  }

  playMeshHopPing(freq = 440) {
    const now = this.ctx.currentTime;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();

    osc.type = 'triangle';
    osc.frequency.setValueAtTime(freq, now);
    osc.frequency.exponentialRampToValueAtTime(freq * 0.5, now + 0.2);

    gain.gain.setValueAtTime(0.2, now);
    gain.gain.exponentialRampToValueAtTime(0.001, now + 0.28);

    osc.connect(gain);
    gain.connect(this.masterGain);

    osc.start(now);
    osc.stop(now + 0.28);
  }

  playCryptoLock() {
    const now = this.ctx.currentTime;
    [783.99, 1567.98].forEach((freq, idx) => {
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();
      osc.type = 'sine';
      osc.frequency.setValueAtTime(freq, now + idx * 0.04);

      gain.gain.setValueAtTime(0.22, now + idx * 0.04);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + idx * 0.04 + 0.5);

      osc.connect(gain);
      gain.connect(this.masterGain);

      osc.start(now + idx * 0.04);
      osc.stop(now + idx * 0.04 + 0.5);
    });
  }

  playLedgerSyncChime() {
    const now = this.ctx.currentTime;
    [523.25, 659.25, 783.99].forEach((freq, idx) => {
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();
      osc.type = 'sine';
      osc.frequency.setValueAtTime(freq, now + idx * 0.05);

      gain.gain.setValueAtTime(0.18, now + idx * 0.05);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + idx * 0.05 + 0.6);

      osc.connect(gain);
      gain.connect(this.masterGain);

      osc.start(now + idx * 0.05);
      osc.stop(now + idx * 0.05 + 0.6);
    });
  }

  playRevealSubDrop() {
    const now = this.ctx.currentTime;
    const subOsc = this.ctx.createOscillator();
    const subGain = this.ctx.createGain();

    subOsc.type = 'sine';
    subOsc.frequency.setValueAtTime(110, now);
    subOsc.frequency.exponentialRampToValueAtTime(36, now + 0.85);

    subGain.gain.setValueAtTime(0.45, now);
    subGain.gain.exponentialRampToValueAtTime(0.001, now + 2.6);

    subOsc.connect(subGain);
    subGain.connect(this.masterGain);

    subOsc.start(now);
    subOsc.stop(now + 2.6);

    [220, 277.18, 329.63, 440].forEach((freq) => {
      const padOsc = this.ctx.createOscillator();
      const padGain = this.ctx.createGain();
      padOsc.type = 'sine';
      padOsc.frequency.setValueAtTime(freq, now + 0.05);

      padGain.gain.setValueAtTime(0.09, now + 0.05);
      padGain.gain.exponentialRampToValueAtTime(0.0001, now + 3.2);

      padOsc.connect(padGain);
      padGain.connect(this.masterGain);

      padOsc.start(now + 0.05);
      padOsc.stop(now + 3.2);
    });
  }
}

window.TeaserAudio = new TeaserAudioEngine();
