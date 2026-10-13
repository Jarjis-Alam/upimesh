/**
 * UPI OFFLINE MESH — 3:4 Cinematic Portrait Teaser Animation Engine
 * Target Resolution: 1440 x 1920 (Portrait 3:4)
 * Pacing & Structure: 24.0s Deterministic Motion Graphics Timeline
 * Matte Black (#050505) + Signal Yellow (#FFD400) Sole Dominant Accent
 */

class TeaserAnimationEngine {
  constructor() {
    this.canvas = document.getElementById('teaser-canvas');
    this.ctx = this.canvas.getContext('2d');

    // Virtual 1440x1920 resolution (3:4 portrait)
    this.vWidth = 1440;
    this.vHeight = 1920;
    this.totalDuration = 24.0; // 24 seconds
    this.currentTime = 0;
    this.isPlaying = false;
    this.lastFrameTimestamp = null;
    this.animationFrameId = null;

    // UI elements
    this.scrubber = document.getElementById('timeline-scrubber');
    this.timecode = document.getElementById('timecode');
    this.sceneTag = document.getElementById('scene-tag');
    this.btnPlay = document.getElementById('btn-play');
    this.btnPlayText = document.getElementById('btn-play-text');
    this.playIcon = document.getElementById('play-icon');
    this.pauseIcon = document.getElementById('pause-icon');
    this.btnRestart = document.getElementById('btn-restart');
    this.btnAudio = document.getElementById('btn-audio');
    this.audioLabel = document.getElementById('audio-label');
    this.audioIcon = document.getElementById('audio-icon');
    this.btnRecord = document.getElementById('btn-record');
    this.btnFullscreen = document.getElementById('btn-fullscreen');
    this.viewport = document.getElementById('viewport-container');

    // Camera state in 3:4 portrait space
    this.camera = { x: 0, y: 0, zoom: 1.0 };
    this.particles = this.createBackgroundField(90);

    // Preload genuine UI screenshot assets
    this.assets = {
      offlinePay: this.loadImage('assets/offline_pay.png'),
      meshRadar: this.loadImage('assets/mesh_radar.png'),
      meshLedger: this.loadImage('assets/mesh_ledger.png')
    };

    // 3:4 Portrait Vertical Mesh Topology (Nodes stacked across vertical canvas)
    this.meshNodes = [
      { id: 'ALICE (0x1A)', x: -260, y: -480, role: 'PAYER' },
      { id: 'NODE 0x7C', x: 240, y: -260, role: 'SEVERED' },
      { id: 'CAROL (0x4F)', x: -220, y: -60, role: 'RELAY' },
      { id: 'RELAY (0x8B)', x: 180, y: 220, role: 'RELAY' },
      { id: 'BRIDGE (0xFF)', x: 0, y: 560, role: 'GATEWAY' }
    ];

    this.idleTimer = null;
    this.setupListeners();
    this.resizeCanvas();
    this.recorder = new window.TeaserRecorder(this.canvas, this);

    // Initial render at t = 0
    this.seek(0);
  }

  loadImage(src) {
    const img = new Image();
    img.src = src;
    img.loaded = false;
    img.onload = () => { img.loaded = true; this.render(this.currentTime); };
    return img;
  }

  createBackgroundField(count) {
    const list = [];
    for (let i = 0; i < count; i++) {
      list.push({
        x: (Math.random() - 0.5) * 1800,
        y: (Math.random() - 0.5) * 2400,
        size: Math.random() * 1.6 + 0.6,
        opacity: Math.random() * 0.35 + 0.1,
        speed: Math.random() * 0.25 + 0.05
      });
    }
    return list;
  }

  setupListeners() {
    window.addEventListener('resize', () => this.resizeCanvas());

    this.btnPlay.addEventListener('click', () => this.togglePlay());
    this.btnRestart.addEventListener('click', () => {
      this.seek(0);
      this.play();
    });

    this.scrubber.addEventListener('input', (e) => {
      this.seek(parseFloat(e.target.value));
    });

    this.btnAudio.addEventListener('click', () => {
      const active = window.TeaserAudio.toggleMute();
      this.audioIcon.textContent = active ? '🔊' : '🔇';
      this.audioLabel.textContent = active ? 'SOUND: ON' : 'SOUND: OFF';
    });

    this.btnRecord.addEventListener('click', () => {
      this.recorder.startRecording();
    });

    this.btnFullscreen.addEventListener('click', () => {
      if (!document.fullscreenElement) {
        document.documentElement.requestFullscreen().catch(() => {});
      } else {
        document.exitFullscreen().catch(() => {});
      }
    });

    // Keyboard shortcuts
    window.addEventListener('keydown', (e) => {
      if (e.code === 'Space') {
        e.preventDefault();
        this.togglePlay();
      } else if (e.code === 'KeyR') {
        this.seek(0);
        this.play();
      } else if (e.code === 'KeyM') {
        this.btnAudio.click();
      } else if (e.code === 'KeyF') {
        this.btnFullscreen.click();
      } else if (e.code === 'ArrowRight') {
        this.seek(Math.min(this.totalDuration, this.currentTime + 1.0));
      } else if (e.code === 'ArrowLeft') {
        this.seek(Math.max(0, this.currentTime - 1.0));
      }
    });

    // Auto-fade HUD on user inactivity
    const resetIdle = () => {
      this.viewport.classList.remove('idle-playing');
      clearTimeout(this.idleTimer);
      if (this.isPlaying) {
        this.idleTimer = setTimeout(() => {
          this.viewport.classList.add('idle-playing');
        }, 2200);
      }
    };
    window.addEventListener('mousemove', resetIdle);
    window.addEventListener('click', resetIdle);
  }

  resizeCanvas() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.canvas.width = this.vWidth * dpr;
    this.canvas.height = this.vHeight * dpr;
    this.ctx.resetTransform();
    this.ctx.scale(dpr, dpr);
    this.render(this.currentTime);
  }

  togglePlay() {
    if (this.isPlaying) {
      this.pause();
    } else {
      if (this.currentTime >= this.totalDuration) {
        this.seek(0);
      }
      this.play();
    }
  }

  play() {
    if (this.isPlaying) return;
    this.isPlaying = true;
    this.btnPlayText.textContent = 'PAUSE';
    this.playIcon.style.display = 'none';
    this.pauseIcon.style.display = 'inline-block';
    this.lastFrameTimestamp = performance.now();
    window.TeaserAudio.syncPlayback(true, this.currentTime);
    this.loop(this.lastFrameTimestamp);

    this.idleTimer = setTimeout(() => {
      this.viewport.classList.add('idle-playing');
    }, 2000);
  }

  pause() {
    this.isPlaying = false;
    this.btnPlayText.textContent = 'PLAY';
    this.playIcon.style.display = 'inline-block';
    this.pauseIcon.style.display = 'none';
    if (this.animationFrameId) {
      cancelAnimationFrame(this.animationFrameId);
      this.animationFrameId = null;
    }
    window.TeaserAudio.syncPlayback(false, this.currentTime);
    this.viewport.classList.remove('idle-playing');
    clearTimeout(this.idleTimer);
  }

  loop(timestamp) {
    if (!this.isPlaying) return;
    const deltaSeconds = (timestamp - this.lastFrameTimestamp) / 1000;
    this.lastFrameTimestamp = timestamp;

    const nextTime = this.currentTime + deltaSeconds;
    if (nextTime >= this.totalDuration) {
      this.seek(this.totalDuration);
      this.pause();
      return;
    }

    this.seek(nextTime);
    this.animationFrameId = requestAnimationFrame((t) => this.loop(t));
  }

  seek(t) {
    const prevT = this.currentTime;
    this.currentTime = Math.max(0, Math.min(this.totalDuration, t));
    this.scrubber.value = this.currentTime.toString();

    // Timecode string format MM:SS.SS
    const mins = Math.floor(this.currentTime / 60).toString().padStart(2, '0');
    const secs = (this.currentTime % 60).toFixed(2).padStart(5, '0');
    this.timecode.textContent = `${mins}:${secs} / 00:24.00`;

    // Audio cue trigger & sync
    window.TeaserAudio.onTimeUpdate(this.currentTime, prevT);
    window.TeaserAudio.seek(this.currentTime);

    // Update scene tag
    if (this.currentTime < 3.2) {
      this.sceneTag.textContent = '01 // THE HOOK';
    } else if (this.currentTime < 7.2) {
      this.sceneTag.textContent = '02 // THE CONCEPT';
    } else if (this.currentTime < 12.2) {
      this.sceneTag.textContent = '03 // THE MESH';
    } else if (this.currentTime < 16.2) {
      this.sceneTag.textContent = '04 // TRUST & RESILIENCE';
    } else if (this.currentTime < 20.0) {
      this.sceneTag.textContent = '05 // THE FUTURE';
    } else {
      this.sceneTag.textContent = '06 // BRAND REVEAL';
    }

    this.render(this.currentTime);
  }

  // =========================================================================
  // Deterministic Render Function for 1440 x 1920 Portrait Canvas
  // =========================================================================
  render(t) {
    const ctx = this.ctx;
    const w = this.vWidth;
    const h = this.vHeight;
    const cx = w / 2;
    const cy = h / 2;

    // Matte black canvas clear (#050505)
    ctx.fillStyle = '#050505';
    ctx.fillRect(0, 0, w, h);

    // Dynamic camera in 3:4 portrait
    this.updateCamera(t);

    ctx.save();
    ctx.translate(cx, cy);
    ctx.scale(this.camera.zoom, this.camera.zoom);
    ctx.translate(-this.camera.x, -this.camera.y);

    // 1. Technical Coordinate Grid & Radar Concentrics
    this.drawPrecisionGrid(ctx, t);

    // 2. Ambient Particles
    this.drawParticleField(ctx, t);

    // 3. Render 6 Cinematic Story Scenes
    if (t < 3.2) {
      this.renderScene1_Hook(ctx, t);
    } else if (t < 7.2) {
      this.renderScene2_Concept(ctx, t);
    } else if (t < 12.2) {
      this.renderScene3_Mesh(ctx, t);
    } else if (t < 16.2) {
      this.renderScene4_Trust(ctx, t);
    } else if (t < 20.0) {
      this.renderScene5_Future(ctx, t);
    } else {
      this.renderScene6_BrandReveal(ctx, t);
    }

    ctx.restore();

    // 4. Fixed Frame Brackets & Bottom Telemetry
    this.drawGlobalFrameBrackets(ctx, t);
  }

  updateCamera(t) {
    if (t < 3.2) {
      // Scene 1: Camera pushes in on phone in top center
      const p = t / 3.2;
      this.camera.x = 0;
      this.camera.y = -120 + p * 60;
      this.camera.zoom = 1.0 + p * 0.08;
    } else if (t < 7.2) {
      // Scene 2: Vertical camera travel from Payer phone down to receiving phone
      const p = (t - 3.2) / 4.0;
      this.camera.x = 0;
      this.camera.y = -80 + p * 160;
      this.camera.zoom = 1.05 - p * 0.05;
    } else if (t < 12.2) {
      // Scene 3: Pull back to wide 3:4 portrait mesh view with vertical tracking
      const p = (t - 7.2) / 5.0;
      this.camera.zoom = 0.92;
      this.camera.x = Math.sin(p * Math.PI) * 20;
      this.camera.y = -180 + p * 260; // Smooth vertical pan following packet down
    } else if (t < 16.2) {
      // Scene 4: Cryptographic seal close-up at center
      const p = (t - 12.2) / 4.0;
      this.camera.x = 0;
      this.camera.y = -20;
      this.camera.zoom = 1.1 + Math.sin(p * Math.PI) * 0.04;
    } else if (t < 20.0) {
      // Scene 5: Ledger convergence
      const p = (t - 16.2) / 3.8;
      this.camera.x = 0;
      this.camera.y = 40 * (1 - p);
      this.camera.zoom = 0.98 + p * 0.04;
    } else {
      // Scene 6: Brand reveal monumental hold
      const p = (t - 20.0) / 4.0;
      this.camera.x = 0;
      this.camera.y = 0;
      this.camera.zoom = 1.0 + p * 0.02;
    }
  }

  drawPrecisionGrid(ctx, t) {
    ctx.save();
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.03)';
    ctx.lineWidth = 1;

    const gridSize = 100;
    const halfW = 900;
    const halfH = 1200;

    ctx.beginPath();
    for (let x = -halfW; x <= halfW; x += gridSize) {
      ctx.moveTo(x, -halfH);
      ctx.lineTo(x, halfH);
    }
    for (let y = -halfH; y <= halfH; y += gridSize) {
      ctx.moveTo(-halfW, y);
      ctx.lineTo(halfW, y);
    }
    ctx.stroke();

    // Subtle yellow coordinate crosses
    ctx.strokeStyle = 'rgba(255, 212, 0, 0.12)';
    ctx.beginPath();
    for (let x = -400; x <= 400; x += 200) {
      for (let y = -600; y <= 600; y += 300) {
        ctx.moveTo(x - 6, y); ctx.lineTo(x + 6, y);
        ctx.moveTo(x, y - 6); ctx.lineTo(x, y + 6);
      }
    }
    ctx.stroke();

    // Concentric radar rings centered
    ctx.strokeStyle = 'rgba(255, 212, 0, 0.06)';
    ctx.beginPath();
    ctx.arc(0, 0, 360, 0, Math.PI * 2);
    ctx.arc(0, 0, 680, 0, Math.PI * 2);
    ctx.stroke();

    ctx.restore();
  }

  drawParticleField(ctx, t) {
    ctx.save();
    ctx.fillStyle = '#FFD400';
    for (let p of this.particles) {
      const currentY = (p.y + t * p.speed * 45) % 2400 - 1200;
      ctx.globalAlpha = p.opacity * 0.45;
      ctx.beginPath();
      ctx.arc(p.x, currentY, p.size, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }

  // =========================================================================
  // SCENE 1: THE HOOK (0.0s – 3.2s)
  // "WHAT IF CONNECTIVITY DISAPPEARED?"
  // Close-up of premium smartphone emerging from darkness, signal drops to 0
  // =========================================================================
  renderScene1_Hook(ctx, t) {
    ctx.save();
    const st = t; // 0.0s to 3.2s
    const isDisconnecting = st >= 1.2;

    // Headline at Top (Centered safe area)
    const titleAlpha = Math.min(1, st / 0.7);
    ctx.globalAlpha = titleAlpha;
    ctx.font = '800 68px "Bricolage Grotesque", sans-serif';
    ctx.fillStyle = '#F5F5F5';
    ctx.textAlign = 'center';
    ctx.letterSpacing = '-0.02em';
    ctx.fillText('WHAT IF', 0, -560);
    ctx.fillText('CONNECTIVITY', 0, -485);
    ctx.fillText('DISAPPEARED?', 0, -410);

    // Premium Smartphone Vector Mockup
    const phoneW = 460;
    const phoneH = 800;
    const phoneY = 160;

    ctx.save();
    ctx.translate(0, phoneY);

    // Titanium chassis shadow & border
    ctx.shadowColor = 'rgba(0, 0, 0, 0.9)';
    ctx.shadowBlur = 60;
    ctx.fillStyle = '#080a0e';
    this.roundRect(ctx, -phoneW / 2, -phoneH / 2, phoneW, phoneH, 48, true, false);
    ctx.shadowBlur = 0;

    // Metallic bezel border
    ctx.strokeStyle = '#22262e';
    ctx.lineWidth = 4;
    this.roundRect(ctx, -phoneW / 2, -phoneH / 2, phoneW, phoneH, 48, false, true);

    // Screen bezel & glass
    ctx.fillStyle = '#050608';
    this.roundRect(ctx, -phoneW / 2 + 12, -phoneH / 2 + 12, phoneW - 24, phoneH - 24, 40, true, false);

    // Dynamic Island
    ctx.fillStyle = '#000000';
    this.roundRect(ctx, -75, -phoneH / 2 + 20, 150, 32, 16, true, false);

    // Status Bar Items
    ctx.font = '600 15px "JetBrains Mono", monospace';
    ctx.fillStyle = '#FFFFFF';
    ctx.textAlign = 'left';
    ctx.fillText('9:41', -phoneW / 2 + 40, -phoneH / 2 + 42);

    // Cellular Signal Bars (Drain at t >= 1.2s)
    const activeBars = st < 1.2 ? 4 : (st < 1.6 ? 2 : (st < 1.9 ? 1 : 0));
    const barX = phoneW / 2 - 120;
    const barY = -phoneH / 2 + 28;
    for (let b = 0; b < 4; b++) {
      const bh = 6 + b * 5;
      ctx.fillStyle = b < activeBars ? '#FFD400' : 'rgba(255, 255, 255, 0.15)';
      ctx.fillRect(barX + b * 11, barY + (20 - bh), 7, bh);
    }

    // Battery Icon
    ctx.strokeStyle = '#FFFFFF';
    ctx.lineWidth = 1.5;
    ctx.strokeRect(barX + 54, barY + 4, 24, 14);
    ctx.fillRect(barX + 56, barY + 6, 16, 10);

    // Phone Display: UPI Interface Fragment
    const uiY = -120;
    ctx.fillStyle = 'rgba(255, 255, 255, 0.04)';
    this.roundRect(ctx, -180, uiY, 360, 200, 16, true, false);

    ctx.font = '700 13px "JetBrains Mono", monospace';
    ctx.fillStyle = '#8E929E';
    ctx.textAlign = 'center';
    ctx.fillText('UPI PAYMENT INTERFACE', 0, uiY + 40);

    ctx.font = '800 48px "Bricolage Grotesque", sans-serif';
    ctx.fillStyle = '#F5F5F5';
    ctx.fillText('₹ 500.00', 0, uiY + 105);

    // Network Status Pill
    if (isDisconnecting) {
      ctx.fillStyle = 'rgba(255, 51, 68, 0.15)';
      ctx.strokeStyle = '#FF3344';
      ctx.lineWidth = 1.5;
      this.roundRect(ctx, -140, uiY + 130, 280, 36, 18, true, true);

      ctx.font = '700 12px "JetBrains Mono", monospace';
      ctx.fillStyle = '#FF4455';
      ctx.fillText('⚠️ NO SERVICE • OFFLINE', 0, uiY + 153);
    } else {
      ctx.fillStyle = 'rgba(255, 212, 0, 0.1)';
      ctx.strokeStyle = 'rgba(255, 212, 0, 0.4)';
      ctx.lineWidth = 1;
      this.roundRect(ctx, -140, uiY + 130, 280, 36, 18, true, true);

      ctx.font = '700 12px "JetBrains Mono", monospace';
      ctx.fillStyle = '#FFD400';
      ctx.fillText('● CONNECTED', 0, uiY + 153);
    }

    // Yellow Scanline Pulse traveling downward
    if (st >= 1.4) {
      const pulseP = (st - 1.4) / 1.6;
      const pulseY = -phoneH / 2 + pulseP * (phoneH - 40);
      ctx.strokeStyle = 'rgba(255, 212, 0, 0.85)';
      ctx.lineWidth = 2.5;
      ctx.beginPath();
      ctx.moveTo(-phoneW / 2 + 20, pulseY);
      ctx.lineTo(phoneW / 2 - 20, pulseY);
      ctx.stroke();

      // Soft glow aura
      ctx.fillStyle = 'rgba(255, 212, 0, 0.12)';
      ctx.fillRect(-phoneW / 2 + 20, pulseY - 15, phoneW - 40, 30);
    }

    ctx.restore();
    ctx.restore();
  }

  // =========================================================================
  // SCENE 2: THE CONCEPT (3.2s – 7.2s)
  // "PAYMENTS THAT KEEP MOVING."
  // Payment packet emerges from device towards second device without cellular
  // =========================================================================
  renderScene2_Concept(ctx, t) {
    ctx.save();
    const st = t - 3.2; // 0.0s to 4.0s

    // Headline
    ctx.font = '800 64px "Bricolage Grotesque", sans-serif';
    ctx.fillStyle = '#F5F5F5';
    ctx.textAlign = 'center';
    ctx.letterSpacing = '-0.02em';
    ctx.fillText('PAYMENTS', 0, -580);
    ctx.fillStyle = '#FFD400';
    ctx.fillText('THAT KEEP MOVING.', 0, -505);

    ctx.font = '600 16px "JetBrains Mono", monospace';
    ctx.fillStyle = '#8E929E';
    ctx.fillText('LOCAL CRYPTOGRAPHIC SIGNING · ZERO CELLULAR', 0, -445);

    // Two Device Mockups Vertically Staged in 3:4 Portrait
    const dev1Y = -180;
    const dev2Y = 380;
    const devW = 380;
    const devH = 240;

    // Device 1: Sender (Alice - 0x1A)
    ctx.fillStyle = '#0a0d13';
    ctx.strokeStyle = '#FFD400';
    ctx.lineWidth = 2;
    this.roundRect(ctx, -devW / 2, dev1Y - devH / 2, devW, devH, 20, true, true);

    ctx.font = '700 13px "JetBrains Mono", monospace';
    ctx.fillStyle = '#FFD400';
    ctx.textAlign = 'left';
    ctx.fillText('📱 SENDER WALLET // ALICE (0x1A)', -devW / 2 + 24, dev1Y - devH / 2 + 36);

    ctx.font = '800 36px "Bricolage Grotesque", sans-serif';
    ctx.fillStyle = '#FFFFFF';
    ctx.fillText('₹ 10.00', -devW / 2 + 24, dev1Y + 12);

    ctx.font = '500 12px "JetBrains Mono", monospace';
    ctx.fillStyle = '#8E929E';
    ctx.fillText('NONCE: #00094F · RSASSA-PSS SIGNED', -devW / 2 + 24, dev1Y + 48);

    // Device 2: Receiver / Local Peer (Bob - 0x8B)
    ctx.fillStyle = '#0a0d13';
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.15)';
    ctx.lineWidth = 1.5;
    this.roundRect(ctx, -devW / 2, dev2Y - devH / 2, devW, devH, 20, true, true);

    ctx.font = '700 13px "JetBrains Mono", monospace';
    ctx.fillStyle = '#F5F5F5';
    ctx.fillText('📲 PEER RECEIVER // BOB (0x8B)', -devW / 2 + 24, dev2Y - devH / 2 + 36);

    ctx.font = '600 16px "JetBrains Mono", monospace';
    ctx.fillStyle = '#8E929E';
    ctx.fillText('AWAITING AD-HOC BEACON...', -devW / 2 + 24, dev2Y + 20);

    // Direct Transit Laser Line between Devices
    ctx.strokeStyle = 'rgba(255, 212, 0, 0.3)';
    ctx.lineWidth = 2;
    ctx.setLineDash([8, 8]);
    ctx.beginPath();
    ctx.moveTo(0, dev1Y + devH / 2);
    ctx.lineTo(0, dev2Y - devH / 2);
    ctx.stroke();
    ctx.setLineDash([]);

    // Animated Payment Packet traveling down the laser line
    // Timeline: 0.8s to 3.2s
    if (st >= 0.8) {
      const travelP = Math.min(1, (st - 0.8) / 2.4);
      const easeP = travelP * travelP * (3 - 2 * travelP);
      const startY = dev1Y + devH / 2;
      const endY = dev2Y - devH / 2;
      const packetY = startY + (endY - startY) * easeP;

      // Glow halo
      const grad = ctx.createRadialGradient(0, packetY, 4, 0, packetY, 40);
      grad.addColorStop(0, '#FFD400');
      grad.addColorStop(0.4, 'rgba(255, 212, 0, 0.4)');
      grad.addColorStop(1, 'rgba(255, 212, 0, 0)');
      ctx.fillStyle = grad;
      ctx.beginPath();
      ctx.arc(0, packetY, 40, 0, Math.PI * 2);
      ctx.fill();

      // Packet Capsule Core
      ctx.fillStyle = '#FFFFFF';
      ctx.beginPath();
      ctx.arc(0, packetY, 10, 0, Math.PI * 2);
      ctx.fill();

      // Packet Metadata Pill
      ctx.fillStyle = '#050505';
      ctx.strokeStyle = '#FFD400';
      ctx.lineWidth = 1.5;
      const tagW = 200;
      const tagH = 32;
      this.roundRect(ctx, 30, packetY - tagH / 2, tagW, tagH, 6, true, true);

      ctx.fillStyle = '#FFD400';
      ctx.font = '700 11px "JetBrains Mono", monospace';
      ctx.textAlign = 'center';
      ctx.fillText('₹10 [ENCRYPTED PAYLOAD]', 30 + tagW / 2, packetY + 4);
    }

    ctx.restore();
  }

  // =========================================================================
  // SCENE 3: THE MESH (7.2s – 12.2s) [VISUAL HIGHLIGHT OF THE TEASER]
  // "PEER-TO-PEER. MESH-POWERED. OFFLINE-FIRST."
  // Multi-hop vertical network, broken connections, self-healing reroute
  // =========================================================================
  renderScene3_Mesh(ctx, t) {
    ctx.save();
    const st = t - 7.2; // 0.0s to 5.0s
    const nodes = this.meshNodes;

    // Headline at Top
    ctx.font = '800 60px "Bricolage Grotesque", sans-serif';
    ctx.fillStyle = '#F5F5F5';
    ctx.textAlign = 'center';
    ctx.letterSpacing = '-0.02em';
    ctx.fillText('PEER-TO-PEER.', 0, -680);
    ctx.fillStyle = '#FFD400';
    ctx.fillText('MESH-POWERED.', 0, -615);
    ctx.fillStyle = '#F5F5F5';
    ctx.fillText('OFFLINE-FIRST.', 0, -550);

    // 1. Broken Connection Link (Alice -> Node 0x7C)
    // Dropping and dissolving at st >= 1.2s
    if (st < 2.0) {
      const dropAlpha = st < 1.2 ? 0.7 : Math.max(0, 1 - (st - 1.2) / 0.8);
      ctx.strokeStyle = st < 1.2 ? 'rgba(255, 255, 255, 0.3)' : 'rgba(255, 51, 68, 0.85)';
      ctx.lineWidth = 2.5;
      ctx.setLineDash([8, 8]);
      ctx.beginPath();
      ctx.moveTo(nodes[0].x, nodes[0].y);
      ctx.lineTo(nodes[1].x, nodes[1].y);
      ctx.stroke();
      ctx.setLineDash([]);

      if (st >= 1.2) {
        ctx.fillStyle = '#FF3344';
        ctx.font = '700 13px "JetBrains Mono", monospace';
        ctx.fillText('⚡ LINK FAILED', (nodes[0].x + nodes[1].x) / 2 + 10, (nodes[0].y + nodes[1].y) / 2);
      }
    }

    // 2. Self-Healing Active Relay Route
    // Hop 1: Alice (0) -> Carol (2) (sparks at st >= 1.3s)
    // Hop 2: Carol (2) -> Relay (3) (sparks at st >= 2.2s)
    // Hop 3: Relay (3) -> Bridge (4) (sparks at st >= 3.2s)
    const hops = [
      { from: 0, to: 2, startAt: 1.3, ttl: 5 },
      { from: 2, to: 3, startAt: 2.2, ttl: 4 },
      { from: 3, to: 4, startAt: 3.2, ttl: 3 }
    ];

    for (let hop of hops) {
      if (st >= hop.startAt) {
        const linkProgress = Math.min(1, (st - hop.startAt) / 0.4);
        const nA = nodes[hop.from];
        const nB = nodes[hop.to];

        ctx.strokeStyle = '#FFD400';
        ctx.lineWidth = 3;
        ctx.beginPath();
        ctx.moveTo(nA.x, nA.y);
        ctx.lineTo(nA.x + (nB.x - nA.x) * linkProgress, nA.y + (nB.y - nA.y) * linkProgress);
        ctx.stroke();

        // Pulsing directional node beacon
        const midX = (nA.x + nB.x) / 2;
        const midY = (nA.y + nB.y) / 2;
        ctx.fillStyle = 'rgba(255, 212, 0, 0.6)';
        ctx.beginPath();
        ctx.arc(midX, midY, 4, 0, Math.PI * 2);
        ctx.fill();
      }
    }

    // 3. Packet Traveling Down the Vertical Transit Rail
    // 1.4s -> 2.3s: Hop 1
    // 2.3s -> 3.3s: Hop 2
    // 3.3s -> 4.4s: Hop 3
    if (st >= 1.4 && st <= 4.8) {
      let curA, curB, progress, ttlNum;
      if (st < 2.3) {
        curA = nodes[0]; curB = nodes[2]; progress = (st - 1.4) / 0.9; ttlNum = 5;
      } else if (st < 3.3) {
        curA = nodes[2]; curB = nodes[3]; progress = (st - 2.3) / 1.0; ttlNum = 4;
      } else {
        curA = nodes[3]; curB = nodes[4]; progress = (st - 3.3) / 1.1; ttlNum = 3;
      }

      const easeP = progress * progress * (3 - 2 * progress);
      const px = curA.x + (curB.x - curA.x) * easeP;
      const py = curA.y + (curB.y - curA.y) * easeP;

      // Glow halo
      const grad = ctx.createRadialGradient(px, py, 4, px, py, 36);
      grad.addColorStop(0, '#FFD400');
      grad.addColorStop(0.5, 'rgba(255, 212, 0, 0.35)');
      grad.addColorStop(1, 'rgba(255, 212, 0, 0)');
      ctx.fillStyle = grad;
      ctx.beginPath();
      ctx.arc(px, py, 36, 0, Math.PI * 2);
      ctx.fill();

      // Core
      ctx.fillStyle = '#FFFFFF';
      ctx.beginPath();
      ctx.arc(px, py, 9, 0, Math.PI * 2);
      ctx.fill();

      // Telemetry HUD Card
      ctx.fillStyle = '#050505';
      ctx.strokeStyle = '#FFD400';
      ctx.lineWidth = 1.5;
      const cardW = 180;
      const cardH = 28;
      this.roundRect(ctx, px + 18, py - cardH / 2, cardW, cardH, 4, true, true);

      ctx.fillStyle = '#FFD400';
      ctx.font = '700 11px "JetBrains Mono", monospace';
      ctx.textAlign = 'center';
      ctx.fillText(`HOP // TTL: ${ttlNum}`, px + 18 + cardW / 2, py + 4);
    }

    // 4. Render Nodes
    for (let i = 0; i < nodes.length; i++) {
      const node = nodes[i];
      const isSevered = (node.role === 'SEVERED' && st >= 1.2);
      const isGateway = node.role === 'GATEWAY';

      // Concentric pulse
      ctx.strokeStyle = isSevered ? 'rgba(255, 51, 68, 0.4)' : (isGateway ? '#FFD400' : 'rgba(255, 212, 0, 0.3)');
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.arc(node.x, node.y, 24, 0, Math.PI * 2);
      ctx.stroke();

      // Node Body
      ctx.fillStyle = isSevered ? '#1a0608' : '#0d1017';
      ctx.beginPath();
      ctx.arc(node.x, node.y, 16, 0, Math.PI * 2);
      ctx.fill();

      // Node Center Dot
      ctx.fillStyle = isSevered ? '#FF3344' : (isGateway ? '#FFD400' : '#FFFFFF');
      ctx.beginPath();
      ctx.arc(node.x, node.y, isGateway ? 8 : 6, 0, Math.PI * 2);
      ctx.fill();

      // Node Label
      ctx.fillStyle = isSevered ? '#FF4455' : '#F5F5F5';
      ctx.font = '700 13px "JetBrains Mono", monospace';
      ctx.textAlign = 'center';
      ctx.fillText(node.id, node.x, node.y + 44);

      ctx.fillStyle = isSevered ? 'rgba(255, 60, 60, 0.7)' : '#FFD400';
      ctx.font = '600 11px "JetBrains Mono", monospace';
      ctx.fillText(node.role, node.x, node.y + 60);
    }

    ctx.restore();
  }

  // =========================================================================
  // SCENE 4: TRUST AND RESILIENCE (12.2s – 16.2s)
  // "SIGNED. ENCRYPTED. DESIGNED FOR RESILIENCE."
  // Abstract signed payment instruction, cryptographic motif
  // =========================================================================
  renderScene4_Trust(ctx, t) {
    ctx.save();
    const st = t - 12.2; // 0.0s to 4.0s

    // Headline
    ctx.font = '800 56px "Bricolage Grotesque", sans-serif';
    ctx.fillStyle = '#F5F5F5';
    ctx.textAlign = 'center';
    ctx.letterSpacing = '-0.02em';
    ctx.fillText('SIGNED. ENCRYPTED.', 0, -560);
    ctx.fillStyle = '#FFD400';
    ctx.fillText('DESIGNED FOR RESILIENCE.', 0, -495);

    // Cryptographic Dial Core in 3:4 portrait center
    const rotSpeed = st * 0.9;
    const outerR = 260;
    const midR = 190;
    const innerR = 120;

    // Outer Degree Ring
    ctx.save();
    ctx.rotate(rotSpeed * 0.3);
    ctx.strokeStyle = 'rgba(255, 212, 0, 0.35)';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(0, -20, outerR, 0, Math.PI * 2);
    ctx.stroke();

    for (let deg = 0; deg < 360; deg += 10) {
      const rad = (deg * Math.PI) / 180;
      const isMajor = deg % 30 === 0;
      const len = isMajor ? 16 : 8;
      ctx.strokeStyle = isMajor ? '#FFD400' : 'rgba(255, 255, 255, 0.2)';
      ctx.beginPath();
      ctx.moveTo(Math.cos(rad) * outerR, -20 + Math.sin(rad) * outerR);
      ctx.lineTo(Math.cos(rad) * (outerR - len), -20 + Math.sin(rad) * (outerR - len));
      ctx.stroke();
    }
    ctx.restore();

    // Middle Ring with Dashes
    ctx.save();
    ctx.rotate(-rotSpeed * 0.6);
    ctx.strokeStyle = '#FFD400';
    ctx.lineWidth = 3;
    ctx.setLineDash([50, 30, 20, 30]);
    ctx.beginPath();
    ctx.arc(0, -20, midR, 0, Math.PI * 2);
    ctx.stroke();
    ctx.restore();

    // Scrolling SHA-256 Hex Fragments Ring
    ctx.save();
    ctx.rotate(rotSpeed * 0.25);
    ctx.font = '700 11px "JetBrains Mono", monospace';
    ctx.fillStyle = 'rgba(255, 212, 0, 0.85)';
    ctx.textAlign = 'center';
    const hashes = ['7F83B165', 'C44298FC', '1C149AFB', 'F4C8996F', 'B92427AE', '41E4649B', '934CA495', '991B7852'];
    for (let i = 0; i < 8; i++) {
      const angle = (i * Math.PI) / 4;
      ctx.save();
      ctx.translate(0, -20);
      ctx.rotate(angle);
      ctx.fillText(hashes[i], 0, -innerR - 14);
      ctx.restore();
    }
    ctx.restore();

    // Key Lock Shackle & Body Glyph at (0, -20)
    ctx.save();
    ctx.translate(0, -20);
    ctx.strokeStyle = '#FFD400';
    ctx.lineWidth = 4;
    ctx.fillStyle = '#050505';

    // Shackle
    ctx.beginPath();
    ctx.arc(0, -18, 30, Math.PI, 0, false);
    ctx.lineTo(30, 8);
    ctx.lineTo(-30, 8);
    ctx.stroke();

    // Lock Body
    this.roundRect(ctx, -46, 6, 92, 70, 10, true, true);

    // Keyhole
    ctx.fillStyle = '#FFD400';
    ctx.beginPath();
    ctx.arc(0, 32, 7, 0, Math.PI * 2);
    ctx.rect(-3.5, 32, 7, 18);
    ctx.fill();
    ctx.restore();

    // Expanding Verification Shockwave at st >= 1.5s
    if (st >= 1.5) {
      const snapP = Math.min(1, (st - 1.5) / 0.6);
      ctx.strokeStyle = `rgba(255, 212, 0, ${1 - snapP})`;
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(0, -20, 100 + snapP * 240, 0, Math.PI * 2);
      ctx.stroke();
    }

    // Trust Cards & Badges in Lower Area
    const cardY = 360;
    ctx.fillStyle = '#0a0d13';
    ctx.strokeStyle = '#FFD400';
    ctx.lineWidth = 1.5;
    this.roundRect(ctx, -380, cardY, 760, 130, 12, true, true);

    ctx.font = '700 16px "JetBrains Mono", monospace';
    ctx.fillStyle = '#FFD400';
    ctx.textAlign = 'center';
    ctx.fillText('✓ RSASSA-PSS SHA-256 SENDER AUTHENTICATION', 0, cardY + 45);

    ctx.font = '500 14px "JetBrains Mono", monospace';
    ctx.fillStyle = '#F5F5F5';
    ctx.fillText('HYBRID ENVELOPE: RSA-OAEP + AES-256-GCM', 0, cardY + 75);

    ctx.fillStyle = '#8E929E';
    ctx.fillText('ZERO-KNOWLEDGE RELAY PRIVACY · PERSISTENT REPLAY IMMUNITY', 0, cardY + 102);

    ctx.restore();
  }

  // =========================================================================
  // SCENE 5: THE FUTURE (16.2s – 20.0s)
  // "BUILT FOR A WORLD THAT DOESN'T ALWAYS CONNECT."
  // Convergence of pending payment records into minimal double-entry ledger
  // =========================================================================
  renderScene5_Future(ctx, t) {
    ctx.save();
    const st = t - 16.2; // 0.0s to 3.8s
    const progress = st / 3.8;

    // Headline
    ctx.font = '800 54px "Bricolage Grotesque", sans-serif';
    ctx.fillStyle = '#F5F5F5';
    ctx.textAlign = 'center';
    ctx.letterSpacing = '-0.02em';
    ctx.fillText('BUILT FOR A WORLD THAT', 0, -560);
    ctx.fillStyle = '#FFD400';
    ctx.fillText("DOESN'T ALWAYS CONNECT.", 0, -495);

    // Convergence Streams Flying into Center Bridge Ingestion Point
    const streamCount = 20;
    for (let i = 0; i < streamCount; i++) {
      const angle = (i * Math.PI * 2) / streamCount + st * 0.3;
      const initialDist = 600;
      const currentDist = Math.max(30, initialDist * (1 - Math.pow(progress, 1.8)));

      ctx.strokeStyle = i % 2 === 0 ? '#FFD400' : 'rgba(255, 255, 255, 0.3)';
      ctx.lineWidth = i % 2 === 0 ? 2.5 : 1;
      ctx.beginPath();
      ctx.moveTo(Math.cos(angle) * currentDist, -100 + Math.sin(angle) * currentDist);
      ctx.lineTo(Math.cos(angle) * (currentDist + 60), -100 + Math.sin(angle) * (currentDist + 60));
      ctx.stroke();
    }

    // Minimal Double-Entry Ledger Card
    const ledgerY = 120;
    const ledgerW = 680;
    const ledgerH = 340;

    ctx.fillStyle = '#090b10';
    ctx.strokeStyle = '#FFD400';
    ctx.lineWidth = 2;
    this.roundRect(ctx, -ledgerW / 2, ledgerY, ledgerW, ledgerH, 16, true, true);

    // Ledger Header
    ctx.fillStyle = 'rgba(255, 212, 0, 0.08)';
    this.roundRect(ctx, -ledgerW / 2, ledgerY, ledgerW, 56, { tl: 16, tr: 16, bl: 0, br: 0 }, true, false);

    ctx.font = '700 14px "JetBrains Mono", monospace';
    ctx.fillStyle = '#FFD400';
    ctx.textAlign = 'left';
    ctx.fillText('ATOMIC DOUBLE-ENTRY RECONCILIATION', -ledgerW / 2 + 24, ledgerY + 34);

    // Settled Pill Badge
    ctx.fillStyle = '#FFD400';
    this.roundRect(ctx, ledgerW / 2 - 130, ledgerY + 16, 106, 26, 13, true, false);
    ctx.fillStyle = '#000000';
    ctx.font = '800 11px "JetBrains Mono", monospace';
    ctx.textAlign = 'center';
    ctx.fillText('● SETTLED', ledgerW / 2 - 77, ledgerY + 33);

    // Ledger Rows
    const rowY1 = ledgerY + 110;
    ctx.textAlign = 'left';
    ctx.font = '600 16px "JetBrains Mono", monospace';
    ctx.fillStyle = '#F5F5F5';
    ctx.fillText('DEBIT: ALICE (0x1A)', -ledgerW / 2 + 30, rowY1);
    ctx.textAlign = 'right';
    ctx.fillStyle = '#FF4455';
    ctx.fillText('- ₹ 10.00', ledgerW / 2 - 30, rowY1);

    const rowY2 = ledgerY + 175;
    ctx.textAlign = 'left';
    ctx.fillStyle = '#F5F5F5';
    ctx.fillText('CREDIT: BOB (0x8B)', -ledgerW / 2 + 30, rowY2);
    ctx.textAlign = 'right';
    ctx.fillStyle = '#FFD400';
    ctx.fillText('+ ₹ 10.00', ledgerW / 2 - 30, rowY2);

    // Divider
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.1)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(-ledgerW / 2 + 24, ledgerY + 225);
    ctx.lineTo(ledgerW / 2 - 24, ledgerY + 225);
    ctx.stroke();

    // Status Footnote
    ctx.textAlign = 'center';
    ctx.font = '500 13px "JetBrains Mono", monospace';
    ctx.fillStyle = '#8E929E';
    ctx.fillText('MATHEMATICAL PROOF AUDIT · ZERO-LEAKAGE SETTLEMENT', 0, ledgerY + 270);
    ctx.fillStyle = 'rgba(255, 212, 0, 0.7)';
    ctx.fillText('OPPORTUNISTIC BRIDGE SYNC WHEN NETWORK DETECTED', 0, ledgerY + 300);

    ctx.restore();
  }

  // =========================================================================
  // SCENE 6: BRAND REVEAL & HOLD (20.0s – 24.0s)
  // Matching the Exact Poster Structure from the Brag Reference Image
  // Vertical yellow line draws, branches into mesh, and resolves into title
  // =========================================================================
  renderScene6_BrandReveal(ctx, t) {
    ctx.save();
    const st = t - 20.0; // 0.0s to 4.0s
    const enterP = Math.min(1, st / 0.8);
    const easeP = 1 - Math.pow(1 - enterP, 3); // Cubic ease out
    const breath = Math.sin((st - 0.8) * 2) * 0.01;
    const scale = 0.96 + easeP * 0.04 + breath;

    ctx.scale(scale, scale);

    // 1. Vertical Yellow Line drawing into mesh symbol
    const lineLen = Math.min(1, st / 0.6) * 160;
    ctx.strokeStyle = '#FFD400';
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.moveTo(0, -660);
    ctx.lineTo(0, -660 + lineLen);
    ctx.stroke();

    // Mesh branching glyph
    if (st >= 0.4) {
      const branchP = Math.min(1, (st - 0.4) / 0.5);
      ctx.beginPath();
      ctx.moveTo(0, -500);
      ctx.lineTo(-40 * branchP, -460);
      ctx.moveTo(0, -500);
      ctx.lineTo(40 * branchP, -460);
      ctx.stroke();

      // Branch nodes
      ctx.fillStyle = '#FFD400';
      ctx.beginPath();
      ctx.arc(-40 * branchP, -460, 4, 0, Math.PI * 2);
      ctx.arc(40 * branchP, -460, 4, 0, Math.PI * 2);
      ctx.fill();
    }

    // 2. Top Pill Badge: OFFLINE-FIRST P2P PAYMENT ARCHITECTURE
    const pillW = 440;
    const pillH = 36;
    const pillY = -380;
    ctx.strokeStyle = 'rgba(255, 212, 0, 0.6)';
    ctx.lineWidth = 1.5;
    ctx.fillStyle = 'rgba(255, 212, 0, 0.06)';
    this.roundRect(ctx, -pillW / 2, pillY - pillH / 2, pillW, pillH, 18, true, true);

    ctx.font = '700 13px "JetBrains Mono", monospace';
    ctx.fillStyle = '#FFD400';
    ctx.textAlign = 'center';
    ctx.fillText('OFFLINE-FIRST P2P PAYMENT ARCHITECTURE', 0, pillY + 5);

    // 3. Monumental Title: UPI OFFLINE MESH
    ctx.textAlign = 'center';
    ctx.font = '900 92px "Bricolage Grotesque", sans-serif';
    ctx.letterSpacing = '-0.02em';

    // Yellow underglow
    ctx.shadowColor = 'rgba(255, 212, 0, 0.75)';
    ctx.shadowBlur = 45;
    ctx.fillStyle = '#FFFFFF';
    ctx.fillText('UPI OFFLINE MESH', 0, -180);
    ctx.shadowBlur = 0;

    // 4. Tagline: PAYMENTS THAT KEEP MOVING.
    ctx.font = '800 36px "Bricolage Grotesque", sans-serif';
    ctx.fillStyle = '#FFD400';
    ctx.letterSpacing = '0.04em';
    ctx.fillText('PAYMENTS THAT KEEP MOVING.', 0, -80);

    // 5. Sub-copy: Even when connectivity doesn't.
    ctx.font = '400 24px "Inter", sans-serif';
    ctx.fillStyle = '#E2E2E6';
    ctx.fillText("Even when connectivity doesn't.", 0, -20);

    // 6. Subtext Pill Banner: THE FUTURE OF CONNECTED PAYMENTS ISN'T ALWAYS ONLINE.
    const bannerW = 680;
    const bannerH = 40;
    const bannerY = 60;
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.12)';
    ctx.lineWidth = 1;
    ctx.fillStyle = 'rgba(255, 255, 255, 0.02)';
    this.roundRect(ctx, -bannerW / 2, bannerY - bannerH / 2, bannerW, bannerH, 20, true, true);

    ctx.font = '600 13px "JetBrains Mono", monospace';
    ctx.fillStyle = '#94A3B8';
    ctx.letterSpacing = '0.08em';
    ctx.fillText("THE FUTURE OF CONNECTED PAYMENTS ISN'T ALWAYS ONLINE.", 0, bannerY + 5);

    // 7. Prominent "COMING SOON" Pill Button (Matching user's reference image!)
    const btnW = 340;
    const btnH = 68;
    const btnY = 190;

    // Golden drop glow
    ctx.shadowColor = 'rgba(255, 212, 0, 0.85)';
    ctx.shadowBlur = 40;
    ctx.fillStyle = '#FFD400';
    this.roundRect(ctx, -btnW / 2, btnY - btnH / 2, btnW, btnH, 34, true, false);
    ctx.shadowBlur = 0;

    ctx.font = '900 22px "JetBrains Mono", monospace';
    ctx.letterSpacing = '0.22em';
    ctx.fillStyle = '#000000';
    ctx.fillText('COMING SOON', 0, btnY + 8);

    // 8. Fine Disclaimer Footnote
    ctx.font = '500 12px "Inter", sans-serif';
    ctx.fillStyle = 'rgba(255, 255, 255, 0.35)';
    ctx.fillText('Experimental research prototype · Not affiliated with NPCI or commercial banking rails', 0, 640);

    ctx.restore();
  }

  // Global Frame Brackets & Fixed Telemetry Bar at Screen Edge
  drawGlobalFrameBrackets(ctx, t) {
    ctx.save();
    const w = this.vWidth;
    const h = this.vHeight;
    const pad = 36;
    const bLen = 28;

    // 4 Corner Brackets
    ctx.strokeStyle = 'rgba(255, 212, 0, 0.3)';
    ctx.lineWidth = 1.5;

    // TL
    ctx.beginPath();
    ctx.moveTo(pad, pad + bLen); ctx.lineTo(pad, pad); ctx.lineTo(pad + bLen, pad);
    ctx.stroke();

    // TR
    ctx.beginPath();
    ctx.moveTo(w - pad - bLen, pad); ctx.lineTo(w - pad, pad); ctx.lineTo(w - pad, pad + bLen);
    ctx.stroke();

    // BL
    ctx.beginPath();
    ctx.moveTo(pad, h - pad - bLen); ctx.lineTo(pad, h - pad); ctx.lineTo(pad + bLen, h - pad);
    ctx.stroke();

    // BR
    ctx.beginPath();
    ctx.moveTo(w - pad - bLen, h - pad); ctx.lineTo(w - pad, h - pad); ctx.lineTo(w - pad, h - pad - bLen);
    ctx.stroke();

    // Bottom Telemetry Bar (Matching reference image)
    const botY = h - 50;
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.08)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(pad, botY - 24);
    ctx.lineTo(w - pad, botY - 24);
    ctx.stroke();

    ctx.font = '500 11px "JetBrains Mono", monospace';
    ctx.fillStyle = '#8E929E';
    ctx.textAlign = 'left';
    ctx.fillText('● SYSTEM: UPI_OFFLINE_MESH', pad + 10, botY);
    ctx.textAlign = 'center';
    ctx.fillText('SPEC: LOCAL_SIGNING + STORE_AND_FORWARD', w / 2, botY);
    ctx.textAlign = 'right';
    ctx.fillText('STATUS: RESEARCH_EVALUATION', w - pad - 10, botY);

    ctx.restore();
  }

  // Helper: Rounded Rectangle with individual or uniform radii
  roundRect(ctx, x, y, width, height, radius, fill, stroke) {
    if (typeof radius === 'undefined') radius = 5;
    if (typeof radius === 'number') {
      radius = { tl: radius, tr: radius, br: radius, bl: radius };
    } else {
      const defaultRadius = { tl: 0, tr: 0, br: 0, bl: 0 };
      for (let side in defaultRadius) {
        radius[side] = radius[side] || defaultRadius[side];
      }
    }
    ctx.beginPath();
    ctx.moveTo(x + radius.tl, y);
    ctx.lineTo(x + width - radius.tr, y);
    ctx.quadraticCurveTo(x + width, y, x + width, y + radius.tr);
    ctx.lineTo(x + width, y + height - radius.br);
    ctx.quadraticCurveTo(x + width, y + height, x + width - radius.br, y + height);
    ctx.lineTo(x + radius.bl, y + height);
    ctx.quadraticCurveTo(x, y + height, x, y + height - radius.bl);
    ctx.lineTo(x, y + radius.tl);
    ctx.quadraticCurveTo(x, y, x + radius.tl, y);
    ctx.closePath();
    if (fill) ctx.fill();
    if (stroke) ctx.stroke();
  }
}

// Instantiate engine when DOM is ready
window.addEventListener('DOMContentLoaded', () => {
  window.teaserEngine = new TeaserAnimationEngine();
});
