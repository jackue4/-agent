/** A single cancellable timeout: suspended carousels never catch up in a burst. */
export function createAutoplay({advance,canAdvance,delay=5000,setTimer=setTimeout,clearTimer=clearTimeout}) {
  let timer=null,disposed=false;
  const clear=()=>{if(timer!==null){clearTimer(timer);timer=null;}};
  const refresh=()=>{
    if(disposed)return;
    if(!canAdvance()){clear();return;}
    if(timer!==null)return;
    timer=setTimer(()=>{timer=null;if(!disposed&&canAdvance()){advance();refresh();}},delay);
  };
  return {refresh,restart(){clear();refresh();},destroy(){disposed=true;clear();}};
}

export function mountFeaturedAutoplay(root,{host=window,doc=document,delay=5000,setTimer=setTimeout,clearTimer=clearTimeout}={}) {
  const track=root.querySelector('.featured-track');
  const count=track?.querySelectorAll('.featured-slide').length||0;
  if(!track||count<2)return null;
  const motion=host.matchMedia('(prefers-reduced-motion: reduce)');
  let hovered=host.matchMedia('(hover:hover)').matches&&root.matches(':hover'),away=false;
  const pointers=new Set(),cleanups=[];
  const listen=(target,event,fn,options)=>{target.addEventListener(event,fn,options);cleanups.push(()=>target.removeEventListener(event,fn,options));};
  const canAdvance=()=>{
    const bounds=root.getBoundingClientRect();
    const focused=root.contains(doc.activeElement);
    return !motion.matches&&!hovered&&!pointers.size&&!focused&&!away&&!doc.hidden&&!root.hidden&&
      doc.body.dataset.page==='feed'&&!doc.querySelector('dialog[open]')&&track.clientWidth>0&&
      bounds.bottom>0&&bounds.top<host.innerHeight;
  };
  const autoplay=createAutoplay({delay,setTimer,clearTimer,canAdvance,advance(){
    const index=Math.round(track.scrollLeft/track.clientWidth),next=(index+1)%count;
    // Wrap directly instead of flashing every intervening slide on the way back.
    track.scrollTo({left:next*track.clientWidth,behavior:next===0||motion.matches?'instant':'smooth'});
  }});
  const refresh=()=>{root.dataset.autoplay=canAdvance()?'running':'paused';autoplay.refresh();};
  listen(root,'pointerenter',event=>{if(event.pointerType==='mouse'){hovered=true;refresh();}});
  listen(root,'pointerleave',event=>{if(event.pointerType==='mouse'){hovered=false;refresh();}});
  listen(root,'pointerdown',event=>{pointers.add(event.pointerId);refresh();});
  const release=event=>{pointers.delete(event.pointerId);refresh();};
  listen(doc,'pointerup',release);listen(doc,'pointercancel',release);
  listen(doc,'focusin',refresh);
  listen(root,'focusout',()=>host.queueMicrotask(refresh));
  listen(track,'scroll',()=>autoplay.restart(),{passive:true});
  listen(root,'keydown',()=>autoplay.restart());
  listen(doc,'visibilitychange',()=>{if(doc.hidden)pointers.clear();hovered=!doc.hidden&&host.matchMedia('(hover:hover)').matches&&root.matches(':hover');refresh();});
  listen(host,'resize',refresh);
  listen(host,'scroll',refresh,{passive:true});
  listen(host,'pagehide',()=>{away=true;refresh();});
  listen(host,'pageshow',()=>{away=false;refresh();});
  listen(motion,'change',refresh);
  refresh();
  return {refresh,destroy(){autoplay.destroy();for(const cleanup of cleanups)cleanup();delete root.dataset.autoplay;}};
}
