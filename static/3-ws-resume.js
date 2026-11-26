(function(){
  var Native=window.WebSocket;
  function RWS(url,protocols){
    if(!/\/ws\/investigate\//.test(String(url))){return new Native(url,protocols);}
    var self=this,ws=null,done=false,closed=false,tries=0,timer=null;
    self.url=url;self.readyState=0;self.onopen=null;self.onmessage=null;self.onclose=null;self.onerror=null;
    function conn(){
      ws=new Native(url,protocols);
      ws.onopen=function(e){self.readyState=1;if(self.onopen)self.onopen(e);};
      ws.onmessage=function(e){
        try{var t=JSON.parse(e.data).type;if(t==="investigation_complete"||t==="investigation_failed"||t==="error")done=true;}catch(x){}
        if(self.onmessage)self.onmessage(e);
      };
      ws.onerror=function(e){if(self.onerror)self.onerror(e);};
      ws.onclose=function(e){
        if(done||closed||tries>=100){self.readyState=3;if(self.onclose)self.onclose(e);return;}
        tries++;self.readyState=0;timer=setTimeout(conn,3000);
      };
    }
    self.close=function(c,r){closed=true;clearTimeout(timer);self.readyState=3;if(ws)try{ws.close(c,r);}catch(x){}};
    self.send=function(d){if(ws)ws.send(d);};
    document.addEventListener("visibilitychange",function(){
      if(document.visibilityState==="visible"&&!done&&!closed&&ws&&ws.readyState>1){clearTimeout(timer);conn();}
    });
    conn();
  }
  RWS.CONNECTING=0;RWS.OPEN=1;RWS.CLOSING=2;RWS.CLOSED=3;
  window.WebSocket=RWS;
})();
