const REALTIME_ORIGIN="https://game-server-v3-production-ed2c.up.railway.app";
const $=s=>document.querySelector(s);
const elements={status:$("#status"),statusLight:$("#status-light"),connectionDetail:$("#connection-detail"),disconnect:$("#disconnect"),pairingPanel:$("#pairing-panel"),qr:$("#qr"),pairingURL:$("#pairing-url"),phone:$("#phone"),clubItems:[...document.querySelectorAll("#club-list li")],shotClub:$("#shot-club"),shotCurve:$("#shot-curve"),rate:$("#rate"),latency:$("#latency"),session:$("#session"),quaternion:["w","x","y","z"].map(a=>$(`#quaternion-${a}`)),rotation:["x","y","z"].map(a=>$(`#rotation-${a}`)),swingRing:$("#swing-ring"),swingStatus:$("#swing-status"),swingMessage:$("#swing-message"),swingResult:$("#swing-result"),phaseTimeline:$("#phase-timeline"),shotHud:$("#shot-hud"),shotPath:$("#shot-path"),flightBall:$("#flight-ball"),landingMark:$("#landing-mark"),shot:{carry:$("#shot-carry"),total:$("#shot-total"),apex:$("#shot-apex"),launch:$("#shot-launch"),shape:$("#shot-shape"),power:$("#shot-power"),tempo:$("#shot-tempo"),quality:$("#shot-quality")},result:{club:$("#result-club"),duration:$("#result-duration"),backswing:$("#result-backswing"),downswing:$("#result-downswing"),tempo:$("#result-tempo"),rotation:$("#result-rotation"),acceleration:$("#result-acceleration")}};
let socket,updateTimes=[],reconnectTimer,controllerConnected=false,animationFrame,currentSession=null;
const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
function setConnectionState(connected,hasConnected=false){controllerConnected=connected;elements.status.textContent=connected?"Connected":hasConnected?"iPhone Disconnected":"Waiting for iPhone";elements.connectionDetail.textContent=connected?"Connected":hasConnected?"Disconnected":"Waiting";elements.statusLight.className=`status-light ${connected?"connected":hasConnected?"disconnected":"waiting"}`;elements.disconnect.hidden=!connected;elements.pairingPanel.classList.toggle("hidden",connected);if(!connected){updateTimes=[];elements.rate.textContent="—";elements.latency.textContent="—";}}
function format(v){return Number.isFinite(Number(v))?Number(v).toFixed(3):"—";}
function quaternionMatrix({w,x,y,z}){const l=Math.hypot(w,x,y,z)||1;w/=l;x/=l;y/=l;z/=l;return `matrix3d(${[1-2*y*y-2*z*z,2*x*y+2*w*z,2*x*z-2*w*y,0,2*x*y-2*w*z,1-2*x*x-2*z*z,2*y*z+2*w*x,0,2*x*z+2*w*y,2*y*z-2*w*x,1-2*x*x-2*y*y,0,0,0,0,1].join(",")})`;}
function handlePose(p){const now=Date.now();updateTimes.push(now);updateTimes=updateTimes.filter(t=>t>=now-1000);elements.rate.textContent=`${updateTimes.length} Hz`;elements.latency.textContent=`${Math.max(0,now-p.sentAtUnixMilliseconds)} ms`;[p.quaternion.w,p.quaternion.x,p.quaternion.y,p.quaternion.z].forEach((v,i)=>elements.quaternion[i].textContent=format(v));[p.rotationRate.x,p.rotationRate.y,p.rotationRate.z].forEach((v,i)=>elements.rotation[i].textContent=format(v));elements.phone.style.transform=quaternionMatrix(p.quaternion);}
function clubLabel(c){return (c||"—").replaceAll("_"," ").replace(/\b\w/g,m=>m.toUpperCase()).replace("Pitching Wedge","PW").replace("Gap Wedge","GW").replace("Sand Wedge","SW").replace("Lob Wedge","LW");}
function selectClub(c){elements.clubItems.forEach(i=>i.classList.toggle("selected",i.dataset.club===c));if(elements.shotClub)elements.shotClub.textContent=clubLabel(c);}
const states={waiting_for_address:["Waiting for address","Tap Set Address on iPhone."],address_calibrated:["Address calibrated","Ready to swing."],waiting_for_swing:["Waiting for swing…","Make one complete swing."],analyzing:["Analyzing swing","Processing 100 Hz motion data."],swing_complete:["Swing complete","Shot received."],invalid:["Invalid swing","Try another complete swing."]};
function handleSwingStatus(p){const [t,m]=states[p.state]||["Swing capture","Waiting for iPhone."];elements.swingStatus.textContent=t;elements.swingMessage.textContent=p.message||m;elements.swingRing.classList.toggle("analyzing",p.state==="analyzing");if(p.state!=="swing_complete")elements.swingResult.hidden=true;}
const clubProfiles={
  "driver":[245,12,36],
  "3_wood":[225,13,34],
  "5_wood":[210,15,32],
  "hybrid":[195,17,30],
  "4_iron":[185,18,29],
  "5_iron":[175,19,28],
  "6_iron":[165,20,27],
  "7_iron":[155,21,26],
  "8_iron":[145,23,25],
  "9_iron":[132,25,24],
  "pitching_wedge":[118,28,23],
  "gap_wedge":[105,30,22],
  "sand_wedge":[90,32,21],
  "lob_wedge":[72,35,20],
  "putter":[20,1,1]
};
function interpretShot(r){
  const [base,loft,baseApex]=clubProfiles[r.club]||clubProfiles["7_iron"];
  const rotation=Math.max(0,Number(r.peakRotationalVelocity)||0);
  const acceleration=Math.max(0,Number(r.peakAcceleration)||0);
  const tempo=Number(r.tempoRatio)||3;
  const analysisConfidence=clamp(Number(r.confidence)||.5,.25,1);

  // Game traits: sensor measurements influence a predictable game model rather
  // than pretending to be measured clubhead/ball physics.
  const rotationPower=clamp((rotation-.8)/10.5,0,1);
  const accelerationPower=clamp((acceleration-.10)/2.8,0,1);
  const power=clamp(rotationPower*.72+accelerationPower*.28,0,1);
  const powerPercent=Math.round(power*100);

  const tempoError=Math.abs(tempo-3);
  const tempoScore=clamp(1-tempoError/3.2,0,1);
  const tempoLabel=tempoScore>=.78?"Great":tempoScore>=.55?"Good":tempoScore>=.3?"Off":"Wild";

  const orientation=Math.max(0,Number(r.maximumRelativeOrientationChangeDegrees)||0);
  const completeness=clamp((orientation-18)/95,0,1);
  const quality=clamp((tempoScore*.45+completeness*.30+analysisConfidence*.25)*100,0,100);
  const qualityFactor=.78+.22*(quality/100);

  const carry=Math.max(1,Math.round(base*Math.pow(power,1.35)*qualityFactor));
  const launch=clamp(loft+(1-power)*3,1,42);
  const apex=Math.max(1,Math.round(baseApex*Math.pow(Math.max(power,.05),1.1)));

  // Direction is deliberately game-like. Larger orientation/tempo errors create
  // more dispersion, while weak shots stay near the center instead of flying wildly.
  const signedSeed=Math.sin(orientation*Math.PI/180*2.25);
  const dispersion=(1-quality/100)*10+3;
  const direction=clamp(signedSeed*dispersion*power,-14,14);
  const curve=clamp((signedSeed*dispersion+(3-tempo)*2.5)*power,-25,25);
  const abs=Math.abs(curve);
  const shape=carry<8?"Short":abs<4?"Straight":curve<0?(abs>14?"Hook":"Draw"):(abs>14?"Slice":"Fade");
  const rollout=r.club.includes("wedge")?Math.max(1,carry*.03):Math.max(1,carry*.07);
  const total=Math.round(carry+rollout);
  const qualityLabel=quality>=80?"Great":quality>=60?"Good":quality>=40?"Okay":"Poor";
  return{carry,total,launch:Math.round(launch),apex,direction,curve,shape,powerPercent,tempoLabel,quality:Math.round(quality),qualityLabel};
}
function rangeYForYards(yards){
  // Match the visual perspective of the labeled range markers. Equal yardage
  // increments compress toward the horizon instead of using a flat pixel scale.
  const anchors=[[0,635],[50,438],[100,401],[150,381],[200,367],[250,356],[300,351]];
  const y=clamp(yards,0,300);
  for(let i=1;i<anchors.length;i++){
    if(y<=anchors[i][0]){
      const [d0,y0]=anchors[i-1],[d1,y1]=anchors[i];
      const t=(y-d0)/(d1-d0);
      return y0+(y1-y0)*t;
    }
  }
  return anchors[anchors.length-1][1];
}
function trajectory(s){const start={x:500,y:635};const endY=rangeYForYards(s.carry);const distance=clamp(s.carry/300,0,1);const lateral=(s.direction+s.curve)*(2.5+4.5*distance);const endX=clamp(500+lateral,110,890);const controlX=clamp(500+s.direction*4-s.curve*3.2,120,880);const rise=clamp(34+s.apex*3.6,34,390);const controlY=clamp(Math.min(start.y,endY)-rise,70,600);return{start,end:{x:endX,y:endY},control:{x:controlX,y:controlY},d:`M ${start.x} ${start.y} Q ${controlX} ${controlY} ${endX} ${endY}`};}
function animateShot(s){cancelAnimationFrame(animationFrame);const t=trajectory(s);elements.shotPath.setAttribute("d",t.d);elements.shotPath.classList.remove("draw");void elements.shotPath.getBoundingClientRect();elements.shotPath.classList.add("draw");elements.landingMark.setAttribute("cx",t.end.x);elements.landingMark.setAttribute("cy",t.end.y);elements.landingMark.classList.remove("show");const start=performance.now(),duration=1500;function frame(now){const p=clamp((now-start)/duration,0,1),u=1-p;const x=u*u*t.start.x+2*u*p*t.control.x+p*p*t.end.x,y=u*u*t.start.y+2*u*p*t.control.y+p*p*t.end.y;elements.flightBall.setAttribute("cx",x);elements.flightBall.setAttribute("cy",y);elements.flightBall.classList.add("airborne");if(p<1)animationFrame=requestAnimationFrame(frame);else{elements.flightBall.classList.remove("airborne");elements.landingMark.classList.add("show");}}animationFrame=requestAnimationFrame(frame);}
function handleSwingResult(r){elements.swingStatus.textContent="Swing complete";elements.swingMessage.textContent=`Analysis quality ${Math.round((r.confidence||0)*100)}%`;elements.swingResult.hidden=false;elements.result.club.textContent=r.club.replaceAll("_"," ");elements.result.duration.textContent=`${r.swingDuration.toFixed(2)} s`;elements.result.backswing.textContent=`${r.backswingDuration.toFixed(2)} s`;elements.result.downswing.textContent=`${r.downswingDuration.toFixed(2)} s`;elements.result.tempo.textContent=`${r.tempoRatio.toFixed(2)} : 1`;elements.result.rotation.textContent=`${r.peakRotationalVelocity.toFixed(2)} rad/s`;elements.result.acceleration.textContent=`${r.peakAcceleration.toFixed(2)} g`;elements.phaseTimeline.replaceChildren();const max=Math.max(r.swingDuration,...Object.values(r.phaseOffsets||{}));for(const [phase,offset] of Object.entries(r.phaseOffsets||{})){const m=document.createElement("span");m.className="phase-marker";m.style.left=`${clamp(offset/max*100,0,100)}%`;m.title=`${phase.replaceAll("_"," ")} ${offset.toFixed(2)}s`;elements.phaseTimeline.append(m);}const shot=interpretShot(r);elements.shotHud.hidden=false;if(elements.shotClub)elements.shotClub.textContent=clubLabel(r.club);if(elements.shotCurve)elements.shotCurve.textContent=`${Math.abs(Math.round(shot.curve))} yd ${shot.curve<0?"L":shot.curve>0?"R":"—"}`;elements.shot.carry.textContent=`${shot.carry} yd`;elements.shot.total.textContent=`${shot.total} yd`;elements.shot.apex.textContent=`${shot.apex} yd`;elements.shot.launch.textContent=`${shot.launch}°`;elements.shot.shape.textContent=shot.shape;if(elements.shot.power)elements.shot.power.textContent=`${shot.powerPercent}%`;if(elements.shot.tempo)elements.shot.tempo.textContent=shot.tempoLabel;if(elements.shot.quality)elements.shot.quality.textContent=`${shot.qualityLabel} ${shot.quality}%`;animateShot(shot);}
function connectDisplay(id){currentSession=id;clearTimeout(reconnectTimer);const realtime=new URL(REALTIME_ORIGIN);const scheme=realtime.protocol==="https:"?"wss":"ws";socket=new WebSocket(`${scheme}://${realtime.host}/display?session=${encodeURIComponent(id)}`);socket.addEventListener("open",()=>console.log("[display] WebSocket connected"));socket.addEventListener("message",e=>{let m;try{m=JSON.parse(e.data)}catch{return}if(m.protocolVersion!==1)return;if(m.type==="displayState"){elements.session.textContent=m.payload.sessionID?.slice(0,8)||id.slice(0,8);setConnectionState(m.payload.connected,m.payload.connected);renderLobby(m.payload)}else if(m.type==="livePose")handlePose(m.payload);else if(m.type==="clubSelection")selectClub(m.payload.club);else if(m.type==="swingStatus")handleSwingStatus(m.payload);else if(m.type==="swingResult")handleSwingResult(m.payload)});socket.addEventListener("close",()=>{reconnectTimer=setTimeout(()=>connectDisplay(id),1500)});socket.addEventListener("error",e=>{console.error("[display] WebSocket error",e);socket.close()});}
elements.disconnect.addEventListener("click",()=>{if(socket?.readyState===WebSocket.OPEN)socket.send(JSON.stringify({protocolVersion:1,type:"disconnectController",payload:{}}));});
function renderLobby(s){const rc=document.querySelector("#room-code"),pl=document.querySelector("#player-list");if(rc&&s.roomCode)rc.textContent=s.roomCode;if(pl)pl.textContent=s.players?.length?s.players.map(p=>`${p.name} ✓`).join("  •  "):"Waiting for players…"}
fetch(`${REALTIME_ORIGIN}/api/session`).then(r=>{if(!r.ok)throw Error(`Session request failed (${r.status})`);return r.json()}).then(s=>{elements.qr.src=`${REALTIME_ORIGIN}/api/qr.png?session=${encodeURIComponent(s.sessionID)}&v=${Date.now()}`;renderLobby(s);elements.pairingURL.textContent=s.pairingURL;elements.session.textContent=s.sessionID.slice(0,8);connectDisplay(s.sessionID)}).catch(e=>{elements.status.textContent=e.message;elements.statusLight.className="status-light disconnected"});
// Keep the browser synchronized with the Node server even if its display WebSocket
// is unavailable. This also provides a reliable fallback for live telemetry.
let lastPolledPoseSequence=null,lastPolledSwingResult=null;
setInterval(()=>currentSession&&fetch(`${REALTIME_ORIGIN}/api/state?session=${encodeURIComponent(currentSession)}`,{cache:"no-store"}).then(r=>r.ok?r.json():null).then(s=>{
  if(!s)return;
  elements.session.textContent=s.sessionID?.slice(0,8)||"—";
  setConnectionState(Boolean(s.connected),Boolean(s.connected));renderLobby(s);
  if(s.latestPose&&s.latestPose.sequenceNumber!==lastPolledPoseSequence){
    lastPolledPoseSequence=s.latestPose.sequenceNumber;
    handlePose(s.latestPose);
  }
  if(s.latestClub)selectClub(s.latestClub.club);
  if(s.latestSwingStatus)handleSwingStatus(s.latestSwingStatus);
  if(s.latestSwingResult&&s.latestSwingResult.resultID!==lastPolledSwingResult){
    lastPolledSwingResult=s.latestSwingResult.resultID;
    handleSwingResult(s.latestSwingResult);
  }
}).catch(e=>console.error("[display] state sync failed",e)),100);
