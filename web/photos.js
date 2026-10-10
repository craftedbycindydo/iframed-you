'use strict';
(() => {
  const $ = id => document.getElementById(id);
  const native = window.Skylit;
  const model = window.SkylitPhotoModel;
  const page = $('photos');
  const settingGrid = document.querySelector('#settings .settings-grid');
  const detailsRow=page.querySelector('.two-cards');
  const heroStatus=document.createElement('p');heroStatus.className='photo-hero-status';page.querySelector('.photo-copy').append(heroStatus);
  const sourcePicker = document.createElement('label');
  sourcePicker.className='photo-source-picker';
  sourcePicker.innerHTML='Show <select id="photo-source-main" aria-label="Photo source"><option value="album">Shared album</option><option value="email">Emailed pictures</option></select>';
  page.querySelector('.page-heading').append(sourcePicker);
  const sourceKey = 'skylit.photoSource';
  let source = localStorage.getItem(sourceKey)==='email'?'email':'album';
  let state = model.normalize({});
  let index = 0, timer = null, playing = true, idle = false, opened = false, interval = 8000, disconnectArmed = false, layer = 0, imageSequence = 0;

  const mailCard = document.createElement('article');
  mailCard.className = 'card photo-mail-card';
  mailCard.innerHTML = '<div class="photo-mail-head"><div><p class="eyebrow">PHOTOS SENT TO YOUR INBOX</p><h2>Email photos</h2></div><button class="quiet" id="photo-check">Check now</button></div><p id="photo-mail-status" role="status"></p><div class="photo-tiles" id="photo-tiles"></div><p class="subtle small">Recent pictures are saved privately on this frame. Messages stay in your inbox.</p>';
  page.append(mailCard);

  const settings = document.createElement('article');
  settings.className = 'card setting-block photo-settings';
  settings.innerHTML = '<h3>Email photo delivery</h3><p class="subtle small">Use a dedicated Gmail account. Turn on Google 2-Step Verification, then create an app password for Skylit. Enter it here on the frame.</p><label for="photo-source">Slideshow source</label><select id="photo-source"><option value="album">Google Photos shared album</option><option value="email">Pictures sent by email</option></select><div id="photo-mail-setup"><label for="photo-email">Gmail address</label><input id="photo-email" type="email" inputmode="email" autocomplete="off" placeholder="Gmail address"><label for="photo-password">Google app password</label><input id="photo-password" type="password" autocomplete="off" autocapitalize="none" spellcheck="false" placeholder="16-character app password"><button id="photo-connect" class="secondary">Connect and check mail</button><p class="tiny">The app password is encrypted in Android’s private storage. Skylit never shows it again or includes it in backups.</p><div class="photo-options"><div><label for="photo-age">Keep pictures from</label><select id="photo-age"><option value="30">Last 30 days</option><option value="90">Last 90 days</option></select></div><div><label for="photo-limit">Maximum pictures</label><select id="photo-limit"><option value="10">10</option><option value="20">20</option><option value="30">30</option><option value="40">40</option><option value="50">50</option></select></div><div><label for="photo-speed">Seconds per picture</label><select id="photo-speed"><option value="5">5</option><option value="8">8</option><option value="12">12</option><option value="20">20</option></select></div></div><button id="photo-disconnect" class="quiet">Disconnect email and erase saved pictures</button><p id="photo-setup-status" class="small" role="status"></p></div>';
  settingGrid.insertBefore(settings, $('calendar-settings'));

  const overlay = document.createElement('div');
  overlay.id = 'photo-player';
  overlay.hidden = true;
  overlay.setAttribute('role','dialog');
  overlay.setAttribute('aria-label','Photo slideshow');
  overlay.innerHTML = '<div class="photo-player-stage"><img class="photo-slide" alt="Picture from your email"><img class="photo-slide" alt="" aria-hidden="true"></div><div class="photo-player-bar"><div class="photo-player-label"><strong>Family photos</strong><span id="photo-counter"></span></div><div class="photo-player-controls"><button id="photo-prev" aria-label="Previous picture">‹</button><button id="photo-pause" aria-label="Pause slideshow">Pause</button><button id="photo-next" aria-label="Next picture">›</button><button id="photo-close" aria-label="Close slideshow">Close</button></div></div><span id="photo-idle-hint">Touch to return to your dashboard</span>';
  document.body.append(overlay);
  const layers=overlay.querySelectorAll('.photo-slide');

  function selectedSource(){return source;}
  function setSource(value){if(value!=='album'&&value!=='email')return;source=value;localStorage.setItem(sourceKey,source);if(native&&native.photoSource)native.photoSource(source);render();}
  function receive(raw){state=model.normalize(raw);render();if(opened){if(!state.photos.length)close();else {index=Math.min(index,state.photos.length-1);show();}}}
  function refresh(){if(!native||!native.photoStatus)return;try{receive(native.photoStatus());}catch(e){$('photo-mail-status').textContent='Could not read the photo status from this frame.';}}
  function render(){
    $('photo-source').value=source;
    $('photo-source-main').value=source;
    $('photo-mail-setup').hidden=source!=='email';
    const timezone=window.SkylitApp.calendarPreferences().timezone;
    $('photo-mail-status').textContent=native?model.caption(state,timezone):'Email photo delivery is available in the Android frame app.';
    $('photo-check').disabled=!native||!state.connected||state.busy;
    if(document.activeElement!==$('photo-email'))$('photo-email').value=state.email;
    $('photo-age').value=String(state.days);
    $('photo-limit').value=String(state.maximum);
    $('photo-speed').value=String(interval/1000);
    $('photo-disconnect').hidden=!state.connected;
    detailsRow.hidden=source==='email'&&!state.photos.length;
    mailCard.hidden=source==='album'||!state.connected;
    const tiles=$('photo-tiles');tiles.replaceChildren();
    state.photos.slice(0,8).forEach((photo,i)=>{const image=document.createElement('img');image.src=photo.url;image.alt='Saved picture '+(i+1);image.loading='lazy';tiles.append(image)});
    const album=source==='album';
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
  function show(){if(!state.photos.length)return;index=Math.min(index,state.photos.length-1);const sequence=++imageSequence,next=1-layer,image=layers[next];image.onload=()=>{if(sequence!==imageSequence||!opened)return;image.classList.add('visible');layers[layer].classList.remove('visible');layer=next;};image.onerror=()=>{if(sequence===imageSequence)$('photo-counter').textContent='Picture unavailable · advancing soon';};image.src=state.photos[index].url;$('photo-counter').textContent=(index+1)+' / '+state.photos.length;}
  function schedule(){clearInterval(timer);timer=null;if(opened&&playing&&state.photos.length>1)timer=setInterval(()=>move(1),interval);}
  function move(amount){if(!state.photos.length)return;index=(index+amount+state.photos.length)%state.photos.length;show();schedule();}
  function open(asIdle){refresh();if(!state.photos.length){$('photo-mail-status').textContent='No pictures are saved yet. Check the account connection in Settings.';return false;}idle=!!asIdle;opened=true;playing=true;index=0;overlay.hidden=false;overlay.classList.toggle('idle',idle);document.body.classList.add('photo-playing');show();schedule();return true;}
  function close(){if(!opened)return;opened=false;++imageSequence;clearInterval(timer);timer=null;overlay.hidden=true;layers.forEach(image=>{image.classList.remove('visible');image.removeAttribute('src')});layer=0;document.body.classList.remove('photo-playing');if(native&&native.localPhotoClosed)native.localPhotoClosed();}
  window.SkylitPhotos={open,close,receive,refresh,selectedSource,setSource};
  $('photo-source').onchange=()=>setSource($('photo-source').value);
  $('photo-source-main').onchange=()=>setSource($('photo-source-main').value);
  page.querySelector('.photo-copy .quiet').onclick=()=>{window.SkylitApp.go('settings');setTimeout(()=>(source==='email'?settings:$('idle-delay')).scrollIntoView({block:'start'}),0)};
  $('photo-check').onclick=()=>{if(native&&native.photoRefresh){native.photoRefresh();$('photo-setup-status').textContent='Checking mail…';setTimeout(refresh,300)}};
  $('photo-connect').onclick=()=>{if(!native||!native.photoConnect){$('photo-setup-status').textContent='Connect from the Android frame.';return;}const email=$('photo-email').value.trim(),password=$('photo-password').value;$('photo-password').value='';if(!native.photoConnect(email,password)){$('photo-setup-status').textContent='Use a Gmail address and its 16-character app password. Wait for any current check to finish.';return;}$('photo-setup-status').textContent='Connection saved. Checking mail…';setSource('email');refresh();};
  for(const id of ['photo-age','photo-limit'])$(id).onchange=()=>{if(native&&native.photoConfigure&&native.photoConfigure(Number($('photo-age').value),Number($('photo-limit').value))){$('photo-setup-status').textContent='Photo limits saved. Older pictures were removed.';refresh();}};
  $('photo-speed').onchange=()=>{interval=Number($('photo-speed').value)*1000;localStorage.setItem('skylit.photoSpeed',String(interval));schedule()};
  const savedSpeed=Number(localStorage.getItem('skylit.photoSpeed'));if([5000,8000,12000,20000].includes(savedSpeed))interval=savedSpeed;
  $('photo-disconnect').onclick=()=>{if(!disconnectArmed){disconnectArmed=true;$('photo-disconnect').textContent='Tap again to erase the photo cache';setTimeout(()=>{disconnectArmed=false;$('photo-disconnect').textContent='Disconnect email and erase saved pictures'},8000);return;}disconnectArmed=false;if(native&&native.photoDisconnect&&native.photoDisconnect()){$('photo-setup-status').textContent='Email disconnected. Saved pictures erased.';refresh();}else $('photo-setup-status').textContent='Wait for the current mail check to finish, then try again.';};
  $('photo-prev').onclick=()=>move(-1);$('photo-next').onclick=()=>move(1);$('photo-pause').onclick=()=>{playing=!playing;$('photo-pause').textContent=playing?'Pause':'Play';schedule()};$('photo-close').onclick=close;
  document.addEventListener('keydown',event=>{if(!opened)return;if(event.key==='Escape')close();if(event.key==='ArrowRight')move(1);if(event.key==='ArrowLeft')move(-1);if(event.key===' '){event.preventDefault();$('photo-pause').click();}});
  $('start-photos').onclick=()=>{if(source==='email'){if(!state.connected){page.querySelector('.photo-copy .quiet').click();return;}if(!state.photos.length){$('photo-check').click();return;}if(native&&native.photoOpen)native.photoOpen(false);else open(false)}else if(!$('album-url').value)page.querySelector('.photo-copy .quiet').click();else if(native)native.openPhotos($('album-url').value,false);else window.open($('album-url').value,'_blank','noopener')};
  $('test-idle').onclick=()=>{if(source==='email'){if(native&&native.photoOpen)native.photoOpen(true);else open(true)}else if(native)native.openPhotos($('album-url').value,true);else if($('album-url').value)window.open($('album-url').value,'_blank','noopener')};
  if(native&&native.photoSource)native.photoSource(source);
  refresh();render();
  window.addEventListener('skylit-preferences',render);
  document.addEventListener('visibilitychange',()=>{if(!document.hidden)refresh()});
})();
