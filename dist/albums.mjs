import {artworkKey,newsArtworkCanvas} from './news-artwork.mjs';
export function imagePaths(post){const paths=Array.isArray(post.image_paths)&&post.image_paths.length?post.image_paths:(post.image_path?[post.image_path]:[]);return paths.filter(p=>typeof p==='string'&&p).slice(0,5);}
export async function renderAlbum(post,signedImage){
 const paths=imagePaths(post);let artwork=null;if(artworkKey(post))try{artwork=await newsArtworkCanvas(post,{signedImage})}catch{}if(artwork)paths.unshift(null);if(!paths.length)return null;
 const album=document.createElement('div');album.className='news-album';album.setAttribute('role','region');album.setAttribute('aria-label','صور الخبر');
 const track=document.createElement('div');track.className='album-track';track.dir='ltr';track.tabIndex=0;album.append(track);
 const count=document.createElement('span');count.className='album-count';count.setAttribute('aria-live','polite');
 const dots=document.createElement('div');dots.className='album-dots';let current=0;
 const go=index=>{current=Math.max(0,Math.min(index,paths.length-1));track.scrollTo({left:current*track.clientWidth,behavior:matchMedia('(prefers-reduced-motion:reduce)').matches?'instant':'smooth'});paint();};
 const paint=()=>{count.textContent=(current+1)+' / '+paths.length;[...dots.children].forEach((dot,i)=>dot.setAttribute('aria-pressed',String(i===current)));};
 for(const [index,path]of paths.entries()){
  const slide=document.createElement('div');slide.className='album-slide';slide.setAttribute('aria-label','الصورة '+(index+1)+' من '+paths.length);
  const img=document.createElement('img');img.alt=(post.title||'صورة الخبر')+' — '+(index+1);img.loading='lazy';if(path===null){artwork.className='artwork-album-canvas';artwork.setAttribute('role','img');artwork.setAttribute('aria-label',post.title+' — تصميم الخبر');slide.append(artwork)}else slide.append(img);track.append(slide);
  const load=async()=>{try{img.src=await signedImage(path);}catch{slide.replaceChildren(retry);}};
  const retry=document.createElement('button');retry.type='button';retry.className='secondary';retry.textContent='إعادة تحميل الصورة';retry.onclick=async()=>{slide.replaceChildren(img);await load();};img.onerror=()=>slide.replaceChildren(retry);if(path!==null)await load();
  const dot=document.createElement('button');dot.type='button';dot.setAttribute('aria-label','عرض الصورة '+(index+1));dot.onclick=()=>go(index);dots.append(dot);
 }
 if(paths.length>1){album.append(count,dots);track.addEventListener('scroll',()=>{const width=track.clientWidth;if(width){current=Math.max(0,Math.min(paths.length-1,Math.round(track.scrollLeft/width)));paint();}},{passive:true});track.addEventListener('keydown',event=>{if(event.key==='ArrowRight'||event.key==='ArrowLeft'){event.preventDefault();go(current+(event.key==='ArrowRight'?1:-1));}});}
 paint();return album;
}
