const crypto=require("node:crypto"),http=require("node:http"),os=require("node:os"),path=require("node:path"),fs=require("node:fs"),QRCode=require("qrcode");
const {WebSocketServer,WebSocket}=require("ws");
const {PROTOCOL_VERSION,chooseAdvertisedHost}=require("./server-config");
const PORT=Number(process.env.PORT||8080),PUBLIC_DIRECTORY=path.join(__dirname,"public"),advertisedHost=chooseAdvertisedHost(os.networkInterfaces(),process.env.GOLFSIM_HOST);
const rooms=new Map(),codes=new Map();
function code(){let c;do c=String(crypto.randomInt(100000,1000000));while(codes.has(c));return c}
function makeRoom(){const r={id:crypto.randomBytes(12).toString("base64url"),token:crypto.randomBytes(24).toString("base64url"),code:code(),controllers:new Map(),displays:new Set(),nextPlayer:1,latest:{}};rooms.set(r.id,r);codes.set(r.code,r.id);return r}
function publicOrigin(req){return process.env.GOLFSIM_PUBLIC_ORIGIN?.replace(/\/$/,"")||`http://${req.headers.host||`${advertisedHost}:${PORT}`}`}
function pairURL(req,r){return `${publicOrigin(req)}/controller.html?session=${encodeURIComponent(r.id)}&token=${encodeURIComponent(r.token)}`}
function send(s,type,payload){if(s?.readyState===WebSocket.OPEN)s.send(JSON.stringify({protocolVersion:PROTOCOL_VERSION,type,payload}))}
function broadcast(r,type,payload){for(const s of r.displays)send(s,type,payload)}
function roomState(r){return{sessionID:r.id,roomCode:r.code,connected:r.controllers.size>0,players:[...r.controllers.values()].map(p=>({id:p.id,name:p.name,club:p.club||"driver"}))}}
function json(res,obj,status=200){res.writeHead(status,{"Content-Type":"application/json","Cache-Control":"no-store"});res.end(JSON.stringify(obj))}
function serveStatic(req,res){const p=req.url==="/"?"/index.html":new URL(req.url,"http://localhost").pathname,f=path.normalize(path.join(PUBLIC_DIRECTORY,p));if(!f.startsWith(PUBLIC_DIRECTORY)){res.writeHead(403).end("Forbidden");return}fs.readFile(f,(e,d)=>{if(e){res.writeHead(404).end("Not found");return}const x=path.extname(f),t={".html":"text/html",".js":"text/javascript",".css":"text/css",".jpg":"image/jpeg",".png":"image/png",".svg":"image/svg+xml"};res.writeHead(200,{"Content-Type":`${t[x]||"application/octet-stream"}; charset=utf-8`,"Cache-Control":"no-store"});res.end(d)})}
const server=http.createServer(async(req,res)=>{res.setHeader("Access-Control-Allow-Origin","*");res.setHeader("Access-Control-Allow-Methods","GET, OPTIONS");if(req.method==="OPTIONS"){res.writeHead(204).end();return}const u=new URL(req.url,`http://${req.headers.host}`);
if(u.pathname==="/api/session"){const r=makeRoom(),url=pairURL(req,r),qrDataURL=await QRCode.toDataURL(url,{errorCorrectionLevel:"M",margin:2,width:360});json(res,{sessionID:r.id,roomCode:r.code,pairingURL:url,qrDataURL});return}
if(u.pathname==="/api/join"){const id=codes.get((u.searchParams.get("code")||"").replace(/\D/g,"")),r=rooms.get(id);if(!r){json(res,{error:"Room not found"},404);return}json(res,{sessionID:r.id,token:r.token,roomCode:r.code,pairingURL:pairURL(req,r)});return}
if(u.pathname==="/api/qr.png"){const r=rooms.get(u.searchParams.get("session"));if(!r){res.writeHead(404).end("Room not found");return}const png=await QRCode.toBuffer(pairURL(req,r),{errorCorrectionLevel:"M",margin:2,width:360,type:"png"});res.writeHead(200,{"Content-Type":"image/png","Cache-Control":"no-store"});res.end(png);return}
if(u.pathname==="/api/state"){const r=rooms.get(u.searchParams.get("session"));if(!r){json(res,{error:"Room not found"},404);return}json(res,{...roomState(r),...r.latest});return}
serveStatic(req,res)});
const wss=new WebSocketServer({noServer:true});
server.on("upgrade",(req,socket,head)=>{const u=new URL(req.url,`http://${req.headers.host}`),role=u.pathname;if(!["/controller","/display"].includes(role)){socket.destroy();return}const r=rooms.get(u.searchParams.get("session"));if(!r||(role==="/controller"&&u.searchParams.get("token")!==r.token)){socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");socket.destroy();return}wss.handleUpgrade(req,socket,head,ws=>wss.emit("connection",ws,req,{role,room:r}))});
wss.on("connection",(socket,req,{role,room:r})=>{socket.isAlive=true;socket.on("pong",()=>socket.isAlive=true);
if(role==="/display"){r.displays.add(socket);send(socket,"displayState",roomState(r));socket.on("close",()=>r.displays.delete(socket));return}
const player={id:crypto.randomBytes(6).toString("base64url"),name:`Player ${r.nextPlayer++}`,club:"driver",socket};r.controllers.set(player.id,player);
socket.on("message",b=>{let m;try{m=JSON.parse(b.toString())}catch{return}if(m.protocolVersion!==PROTOCOL_VERSION||!m.type)return;
if(m.type==="phoneHello"){if(m.payload?.playerName?.trim())player.name=m.payload.playerName.trim().slice(0,24);send(socket,"connectionAccepted",{sessionID:r.id,roomCode:r.code,playerID:player.id,playerName:player.name});broadcast(r,"displayState",roomState(r));return}
if(m.type==="ping"){send(socket,"pong",m.payload);return}
if(m.type==="clubSelection")player.club=m.payload.club||player.club;
if(["livePose","clubSelection","swingStatus","swingResult"].includes(m.type)){const payload={...m.payload,playerID:player.id,playerName:player.name};if(m.type==="livePose")r.latest.latestPose=payload;if(m.type==="clubSelection")r.latest.latestClub=payload;if(m.type==="swingStatus")r.latest.latestSwingStatus=payload;if(m.type==="swingResult")r.latest.latestSwingResult=payload;broadcast(r,m.type,payload);broadcast(r,"displayState",roomState(r))}});
socket.on("close",()=>{r.controllers.delete(player.id);broadcast(r,"displayState",roomState(r))})});
setInterval(()=>{for(const s of wss.clients){if(!s.isAlive){s.terminate();continue}s.isAlive=false;s.ping()}},15000);
server.listen(PORT,"0.0.0.0",()=>console.log(`thegolfgame realtime server: http://localhost:${PORT}`));
