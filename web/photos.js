'use strict';
(() => {
  const $ = id => document.getElementById(id);
  const native = window.Skylit;
  const model = window.SkylitPhotoModel;
  const playback = window.SkylitPhotoPlayback;
  const page = $('photos');
  const detailsRow=page.querySelector('.two-cards');
  const heroStatus=document.createElement('p');heroStatus.className='photo-hero-status';page.querySelector('.photo-copy').append(heroStatus);
  const sourcePicker = document.createElement('label');
  sourcePicker.className='photo-source-picker';
  sourcePicker.innerHTML='Show <select id="photo-source-main" aria-label="Photo source"><option value="album">Shared album</option><option value="email">Emailed pictures</option></select>';
  page.querySelector('.page-heading').append(sourcePicker);
  const sourceKey = 'skylit.photoSource';
  let source = localStorage.getItem(sourceKey)==='email'?'email':'album';
  let state = model.normalize({});
  let index = 0, timer = null, controlsTimer = null, playing = true, idle = false, opened = false, interval = 8000, disconnectArmed = false, layer = 0, imageSequence = 0, zoom = 1, panX = 0, panY = 0, keyboardActivity = false;
  let style=playback.style(localStorage.getItem('skylit.photoStyle'));

  const workspace=document.createElement('div');workspace.className='photo-workspace';
  page.querySelector('.page-heading').after(workspace);

  const mailCard = document.createElement('article');
  mailCard.className = 'card photo-mail-card';
  mailCard.innerHTML = '<div class="photo-mail-head"><div><p class="eyebrow">PICTURES SENT TO YOUR INBOX</p><h2>Photo library</h2><p id="photo-mail-status" role="status"></p></div><div class="photo-mail-actions"><button class="primary" id="photo-play"><span data-icon="play"></span>Slideshow</button><button class="secondary" id="photo-check">Check now</button></div></div><div class="photo-tiles" id="photo-tiles"></div><p class="subtle small">Tap a picture to browse and zoom. Saved pictures stay on this frame; messages stay in your inbox.</p>';
  workspace.append(mailCard);

  const settings = document.createElement('details');
  settings.className = 'card setting-block photo-settings';
  settings.innerHTML = '<summary>Photo settings <span aria-hidden="true">⌄</span></summary><div class="photo-settings-content"><p class="subtle small">Choose the source and how your slideshow looks. Email pictures use a dedicated Gmail account and an app password.</p><label for="photo-source">Photo source</label><select id="photo-source"><option value="album">Google Photos shared album</option><option value="email">Pictures sent by email</option></select><div id="photo-mail-setup"><label for="photo-email">Gmail address</label><input id="photo-email" type="email" inputmode="email" autocomplete="off" placeholder="Gmail address"><label for="photo-password">Google app password</label><input id="photo-password" type="password" autocomplete="off" autocapitalize="none" spellcheck="false" placeholder="16-character app password"><button id="photo-connect" class="secondary">Connect and check mail</button><p class="tiny">The app password is encrypted in Android’s private storage. Skylit never shows it again or includes it in backups.</p><div class="photo-options"><div><label for="photo-style">Slideshow style</label><select id="photo-style"><option value="fade">Soft fade</option><option value="stack">Falling prints</option><option value="collage">Photo collage</option></select></div><div><label for="photo-speed">Seconds per picture</label><select id="photo-speed"><option value="5">5</option><option value="8">8</option><option value="12">12</option><option value="20">20</option></select></div><div><label for="photo-age">Keep pictures from</label><select id="photo-age"><option value="30">Last 30 days</option><option value="90">Last 90 days</option></select></div><div><label for="photo-limit">Maximum pictures</label><select id="photo-limit"><option value="10">10</option><option value="20">20</option><option value="30">30</option><option value="40">40</option><option value="50">50</option></select></div></div><button id="photo-disconnect" class="quiet">Disconnect email and erase saved pictures</button><p id="photo-setup-status" class="small" role="status"></p></div></div>';
  workspace.append(settings);
  const presentation=document.createElement('div');presentation.className='photo-presentation';
  presentation.innerHTML='<h3>Slideshow</h3>';
  const optionFields=settings.querySelectorAll('.photo-options > div');
  presentation.append(optionFields[0],optionFields[1]);
  settings.querySelector('.photo-settings-content').insertBefore(presentation,settings.querySelector('label[for="photo-source"]'));

  const overlay = document.createElement('div');
  overlay.id = 'photo-player';
  overlay.hidden = true;
  overlay.setAttribute('role','dialog');
  overlay.setAttribute('aria-label','Photo slideshow');
  overlay.innerHTML = '<div class="photo-player-stage"><img class="photo-slide" alt="Picture from your email"><img class="photo-slide" alt="" aria-hidden="true"><div class="photo-collage" aria-hidden="true"><img alt=""><img alt=""><img alt=""></div></div><div class="photo-player-bar"><div class="photo-player-label"><strong id="photo-viewer-title">Family photos</strong><span id="photo-counter"></span></div><div class="photo-player-controls"><button id="photo-prev" aria-label="Previous picture">‹</button><button id="photo-pause" aria-label="Pause slideshow">Pause</button><button id="photo-zoom" aria-label="Zoom into picture">Zoom</button><button id="photo-next" aria-label="Next picture">›</button><button id="photo-close" aria-label="Close slideshow">Close</button></div></div><span id="photo-idle-hint">Touch to return to your dashboard</span>';
  document.body.append(overlay);
  const layers=overlay.querySelectorAll('.photo-slide');

  function selectedSource(){return source;}
  function setSource(value){if(value!=='album'&&value!=='email')return;source=value;localStorage.setItem(sourceKey,source);if(native&&native.photoSource)native.photoSource(source);render();}
  function receive(raw){state=model.normalize(raw);render();if(opened){if(!state.photos.length)close();else {index=Math.min(index,state.photos.length-1);show();}}}
  function refresh(){if(!native||!native.photoStatus)return;try{receive(native.photoStatus());}catch(e){$('photo-mail-status').textContent='Could not read the photo status from this frame.';}}
  function renderOverviewPhotos(){
    const items=source==='email'?state.photos.slice(0,3):[];
    const button=$('overview-photos'),host=$('overview-photo-stack');
    button.hidden=!items.length;
    document.querySelector('.overview-grid').classList.toggle('with-photos',items.length>0);
    host.replaceChildren();
    items.forEach((photo,i)=>{const image=document.createElement('img');image.src=photo.url;image.alt='';image.style.setProperty('--photo-angle',playback.angle(i)+'deg');host.append(image)});
  }
  function render(){
    const album=source==='album';
    $('photo-source').value=source;
    $('photo-source-main').value=source;
    $('photo-mail-setup').hidden=source!=='email';
    workspace.hidden=album;
    page.querySelector('.photo-feature').hidden=!album;
    detailsRow.hidden=!album;
    const timezone=window.SkylitApp.calendarPreferences().timezone;
    $('photo-mail-status').textContent=native?model.caption(state,timezone):'Email photo delivery is available in the Android frame app.';
    $('photo-check').disabled=!native||!state.connected||state.busy;
    $('photo-play').disabled=!state.photos.length;
    if(document.activeElement!==$('photo-email'))$('photo-email').value=state.email;
    $('photo-age').value=String(state.days);
    $('photo-limit').value=String(state.maximum);
    $('photo-speed').value=String(interval/1000);
    $('photo-style').value=style;
    $('photo-disconnect').hidden=!state.connected;
    const tiles=$('photo-tiles');tiles.replaceChildren();
    if(!state.photos.length){const empty=document.createElement('p');empty.className='photo-empty';empty.textContent=state.connected?'No pictures saved yet. Tap Check now after sending one to your inbox.':'Connect a dedicated inbox in Photo settings to start your library.';tiles.append(empty)}
    state.photos.forEach((photo,i)=>{const button=document.createElement('button');button.type='button';button.className='photo-tile';button.setAttribute('aria-label','Open picture '+(i+1)+' of '+state.photos.length);const image=document.createElement('img');image.src=photo.url;image.alt='';image.loading='lazy';button.append(image);button.onclick=()=>{if(native&&native.photoBrowse)native.photoBrowse(i);else open(false,i,false)};tiles.append(button)});
    renderOverviewPhotos();
    const headline=page.querySelector('.photo-copy .eyebrow'),title=page.querySelector('.photo-copy h2'),description=page.querySelector('.photo-copy p:not(.eyebrow)');
    headline.textContent=album?'YOUR SHARED GOOGLE PHOTOS ALBUM':'PICTURES SENT TO YOUR INBOX';
    title.textContent=album?'Shared album':'Recent photos';
    description.textContent=album?'Play your Google Photos album full screen.':'A private, on-frame slideshow of recent emailed pictures.';
    heroStatus.textContent=album||state.photos.length?'':model.caption(state,timezone);
    const action=album?'Start slideshow':state.photos.length?'Start slideshow':state.connected?'Check for photos':'Set up email photos';
    const actionButton=$('start-photos');Array.from(actionButton.childNodes).filter(n=>n.nodeType===3).forEach(n=>n.remove());actionButton.append(document.createTextNode(action));const playIcon=actionButton.querySelector('svg');if(playIcon)playIcon.style.display=action==='Start slideshow'?'':'none';
    page.querySelector('.photo-copy .quiet').textContent=album?'Album and timing settings →':'Delivery settings →';
    $('album-status').textContent=album?($('album-url').value?'Your shared album is ready to open.':'Add a shared album link in Settings to get started.'):(state.photos.length?state.photos.length+' pictures are ready to play.':'No saved pictures yet. Connect an account and check mail.');
    const details=page.querySelectorAll('.detail');
    if(details[1]){details[1].querySelector('h3').textContent=album?'One shared album':'Private photo cache';details[1].querySelector('.subtle').textContent=album?'Uses Google’s slideshow. Skylit stores no copies.':'Old pictures are removed automatically. Only resized pictures are saved, without email contents or image metadata.';}
  }
  const stage=overlay.querySelector('.photo-player-stage'),collage=overlay.querySelector('.photo-collage');
  function zoomTo(value){zoom=Math.max(1,Math.min(2.5,value));if(zoom===1){panX=0;panY=0;}stage.style.setProperty('--photo-zoom',String(zoom));stage.style.setProperty('--photo-pan-x',panX+'px');stage.style.setProperty('--photo-pan-y',panY+'px');overlay.classList.toggle('zoomed',zoom>1);$('photo-zoom').textContent=zoom>1?'Fit picture':'Zoom';$('photo-zoom').setAttribute('aria-label',zoom>1?'Fit picture to screen':'Zoom into picture');}
  function revealControls(){if(!opened||idle)return;overlay.classList.remove('controls-hidden');clearTimeout(controlsTimer);controlsTimer=setTimeout(()=>{if(opened&&!idle&&(!keyboardActivity||!overlay.querySelector('.photo-player-bar').contains(document.activeElement)))overlay.classList.add('controls-hidden');},4000);}
  function show(){
    if(!state.photos.length)return;
    index=Math.min(index,state.photos.length-1);
    const sequence=++imageSequence;
    $('photo-counter').textContent=(index+1)+' / '+state.photos.length;
    if(overlay.dataset.style==='collage'){
      const positions=playback.collage(index,state.photos.length);
      collage.dataset.count=String(positions.length);
      Array.from(collage.children).forEach((image,i)=>{
        const position=positions[i];
        image.hidden=position===undefined;
        if(image.hidden)image.removeAttribute('src');
        else image.src=state.photos[position].url;
      });
      collage.classList.remove('is-entering');void collage.offsetWidth;collage.classList.add('is-entering');
      return;
    }
    const previous=layer,next=1-layer,image=layers[next];
    image.style.setProperty('--photo-angle',playback.angle(index)+'deg');
    image.onload=()=>{if(sequence!==imageSequence||!opened)return;image.classList.add('visible');layers[previous].classList.remove('visible');layer=next;};
    image.onerror=()=>{if(sequence===imageSequence)$('photo-counter').textContent='Picture unavailable · advancing soon';};
    image.src=state.photos[index].url;
    if(image.complete&&image.naturalWidth)image.onload();
  }
  function schedule(){clearInterval(timer);timer=null;if(opened&&playing&&state.photos.length>1)timer=setInterval(()=>move(1,false),interval);}
  function move(amount,fromUser){if(!state.photos.length)return;index=(index+amount+state.photos.length)%state.photos.length;zoomTo(1);show();schedule();if(fromUser)revealControls();}
  function open(asIdle,start=0,autoplay=true){
    refresh();if(!state.photos.length){$('photo-mail-status').textContent='No pictures are saved yet. Check the account connection in Photo settings.';return false;}
    idle=!!asIdle;opened=true;playing=!!autoplay;index=Math.max(0,Math.min(state.photos.length-1,Number(start)||0));
    overlay.hidden=false;overlay.classList.toggle('idle',idle);overlay.dataset.style=playing?style:'fade';overlay.classList.remove('controls-hidden');
    overlay.setAttribute('aria-label',playing?'Photo slideshow':'Photo browser');$('photo-viewer-title').textContent=playing?'Family photos':'Browse photos';$('photo-pause').textContent=playing?'Pause':'Play';
    document.body.classList.add('photo-playing');zoomTo(1);show();schedule();revealControls();return true;
  }
  function close(){if(!opened)return;opened=false;++imageSequence;clearInterval(timer);clearTimeout(controlsTimer);timer=null;overlay.hidden=true;layers.forEach(image=>{image.classList.remove('visible');image.removeAttribute('src')});Array.from(collage.children).forEach(image=>image.removeAttribute('src'));layer=0;document.body.classList.remove('photo-playing');if(native&&native.localPhotoClosed)native.localPhotoClosed();}
  window.SkylitPhotos={open,close,receive,refresh,selectedSource,setSource};
  $('photo-source').onchange=()=>setSource($('photo-source').value);
  $('photo-source-main').onchange=()=>setSource($('photo-source-main').value);
  $('overview-photos').onclick=()=>window.SkylitApp.go('photos');
  $('photo-play').onclick=()=>{if(native&&native.photoOpen)native.photoOpen(false);else open(false)};
  page.querySelector('.photo-copy .quiet').onclick=()=>{window.SkylitApp.go('settings');setTimeout(()=>$('idle-delay').scrollIntoView({block:'start'}),0)};
  $('photo-check').onclick=()=>{if(native&&native.photoRefresh){native.photoRefresh();$('photo-setup-status').textContent='Checking mail…';setTimeout(refresh,300)}};
  $('photo-connect').onclick=()=>{if(!native||!native.photoConnect){$('photo-setup-status').textContent='Connect from the Android frame.';return;}const email=$('photo-email').value.trim(),password=$('photo-password').value;$('photo-password').value='';if(!native.photoConnect(email,password)){$('photo-setup-status').textContent='Use a Gmail address and its 16-character app password. Wait for any current check to finish.';return;}$('photo-setup-status').textContent='Connection saved. Checking mail…';setSource('email');refresh();};
  for(const id of ['photo-age','photo-limit'])$(id).onchange=()=>{if(native&&native.photoConfigure&&native.photoConfigure(Number($('photo-age').value),Number($('photo-limit').value))){$('photo-setup-status').textContent='Photo limits saved. Older pictures were removed.';refresh();}};
  $('photo-style').onchange=()=>{style=playback.style($('photo-style').value);localStorage.setItem('skylit.photoStyle',style);if(opened&&playing){overlay.dataset.style=style;show();schedule();}};
  $('photo-speed').onchange=()=>{interval=Number($('photo-speed').value)*1000;localStorage.setItem('skylit.photoSpeed',String(interval));schedule()};
  const savedSpeed=Number(localStorage.getItem('skylit.photoSpeed'));if([5000,8000,12000,20000].includes(savedSpeed))interval=savedSpeed;
  $('photo-disconnect').onclick=()=>{if(!disconnectArmed){disconnectArmed=true;$('photo-disconnect').textContent='Tap again to erase the photo cache';setTimeout(()=>{disconnectArmed=false;$('photo-disconnect').textContent='Disconnect email and erase saved pictures'},8000);return;}disconnectArmed=false;if(native&&native.photoDisconnect&&native.photoDisconnect()){$('photo-setup-status').textContent='Email disconnected. Saved pictures erased.';refresh();}else $('photo-setup-status').textContent='Wait for the current mail check to finish, then try again.';};
  $('photo-prev').onclick=()=>move(-1,true);$('photo-next').onclick=()=>move(1,true);
  $('photo-pause').onclick=()=>{playing=!playing;$('photo-pause').textContent=playing?'Pause':'Play';overlay.dataset.style=playing?style:'fade';show();schedule();revealControls()};
  $('photo-zoom').onclick=()=>{if(playing)$('photo-pause').click();zoomTo(zoom>1?1:1.8);revealControls()};
  $('photo-close').onclick=close;
  overlay.addEventListener('pointermove',()=>{keyboardActivity=false;revealControls()});overlay.addEventListener('pointerdown',()=>{keyboardActivity=false;revealControls()});
  let drag=null;
  stage.addEventListener('pointerdown',event=>{if(zoom<=1)return;drag={x:event.clientX,y:event.clientY,panX,panY};stage.setPointerCapture(event.pointerId)});
  stage.addEventListener('pointermove',event=>{if(!drag)return;panX=drag.panX+event.clientX-drag.x;panY=drag.panY+event.clientY-drag.y;zoomTo(zoom)});
  stage.addEventListener('pointerup',()=>drag=null);stage.addEventListener('pointercancel',()=>drag=null);
  stage.addEventListener('wheel',event=>{if(!opened)return;event.preventDefault();if(playing)$('photo-pause').click();zoomTo(zoom+(event.deltaY<0 ? .25 : -.25));revealControls()},{passive:false});
  document.addEventListener('keydown',event=>{if(!opened)return;keyboardActivity=true;if(event.key==='Escape')close();if(event.key==='ArrowRight')move(1,true);if(event.key==='ArrowLeft')move(-1,true);if(event.key===' '){event.preventDefault();$('photo-pause').click();}if(event.key==='+'||event.key==='='){event.preventDefault();zoomTo(zoom+.25)}if(event.key==='-'){event.preventDefault();zoomTo(zoom-.25)}revealControls();});
  $('start-photos').onclick=()=>{if(source==='email'){if(!state.connected){page.querySelector('.photo-copy .quiet').click();return;}if(!state.photos.length){$('photo-check').click();return;}if(native&&native.photoOpen)native.photoOpen(false);else open(false)}else if(!$('album-url').value)page.querySelector('.photo-copy .quiet').click();else if(native)native.openPhotos($('album-url').value,false);else window.open($('album-url').value,'_blank','noopener')};
  $('test-idle').onclick=()=>{if(source==='email'){if(native&&native.photoOpen)native.photoOpen(true);else open(true)}else if(native)native.openPhotos($('album-url').value,true);else if($('album-url').value)window.open($('album-url').value,'_blank','noopener')};
  if(native&&native.photoSource)native.photoSource(source);
  refresh();render();
  window.addEventListener('skylit-preferences',render);
  document.addEventListener('visibilitychange',()=>{if(!document.hidden)refresh()});
})();
