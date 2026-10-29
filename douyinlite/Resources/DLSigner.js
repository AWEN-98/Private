/* A-Bogus signing port, modified for ES5 JavaScriptCore on iOS 8.
 * Derived from Evil0ctal/Douyin_TikTok_Download_API, Apache-2.0.
 * See ThirdPartyNotices.txt and Apache-2.0.txt. No network/browser dependency.
 */
var DLSigner = (function () {
  var s3='ckdp1h4ZKsUB80/Mfvw36XIgR25+WQAlEi7NLboqYTOPuzmFjJnryx9HVGDaStCe';
  var s4='Dkdpgh2ZmsQB80/MfvV36XI1R45-WUAlEixNLwoqYTOPuzKFjJnry79HbGcaStCe';
  var order=[34,44,56,61,73,29,70,45,35,49,38,66,51,68,28,48,64,47,30,71,26,55,31,69,59,40,62,63,27,72,41,74,57,52,42,39,33,67,53,43,65,46,36,24,60,32,79,80,84,85];
  function bytes(s) { var a=[],i,c; for(i=0;i<s.length;i++){c=s.charCodeAt(i);if(c&65280)a.push(c>>8);a.push(c&255);}return a; }
  function utf8(s) {var t=unescape(encodeURIComponent(s)),a=[],i;for(i=0;i<t.length;i++)a.push(t.charCodeAt(i));return a;}
  function rol(x,n){n%=32;return ((x<<n)|(x>>>(32-n)))>>>0;}
  function sm3(input) {
    var a=typeof input==='string'?utf8(input):input.slice(),bits=a.length*8,i,j,w=[],v=[0x7380166f,0x4914b2b9,0x172442d7,0xda8a0600,0xa96f30bc,0x163138aa,0xe38dee4d,0xb0fb0e4e];
    a.push(128);while(a.length%64!==56)a.push(0);
    for(i=7;i>=0;i--)a.push(Math.floor(bits/Math.pow(256,i))&255);
    for(i=0;i<a.length;i+=64){
      for(j=0;j<16;j++)w[j]=((a[i+j*4]<<24)|(a[i+j*4+1]<<16)|(a[i+j*4+2]<<8)|a[i+j*4+3])>>>0;
      for(j=16;j<68;j++){var x=w[j-16]^w[j-9]^rol(w[j-3],15);w[j]=(x^rol(x,15)^rol(x,23)^rol(w[j-13],7)^w[j-6])>>>0;}
      var A=v[0],B=v[1],C=v[2],D=v[3],E=v[4],F=v[5],G=v[6],H=v[7];
      for(j=0;j<64;j++){
        var ss1=rol((rol(A,12)+E+rol(j<16?0x79cc4519:0x7a879d8a,j))>>>0,7),ss2=ss1^rol(A,12);
        var ff=j<16?(A^B^C):((A&B)|(A&C)|(B&C));
        var gg=j<16?(E^F^G):((E&F)|(~E&G));
        var t1=(ff+D+ss2+(w[j]^w[j+4]>>>0))>>>0,t2=(gg+H+ss1+w[j])>>>0;
        D=C;C=rol(B,9);B=A;A=t1;H=G;G=rol(F,19);F=E;E=(t2^rol(t2,9)^rol(t2,17))>>>0;
      }
      var work=[A,B,C,D,E,F,G,H];for(j=0;j<8;j++)v[j]=(v[j]^work[j])>>>0;
    }
    var out=[];for(i=0;i<8;i++)for(j=3;j>=0;j--)out.push((v[i]>>>(8*j))&255);return out;
  }
  function rc4(key,data){var box=[],i,j=0,t,out=[];for(i=0;i<256;i++)box[255-i]=i;for(i=0;i<256;i++){j=(j*box[i]+j+key[i%key.length])%256;t=box[i];box[i]=box[j];box[j]=t;}i=0;j=0;for(var k=0;k<data.length;k++){i=(i+1)%256;j=(j+box[i])%256;t=box[i];box[i]=box[j];box[j]=t;out.push(data[k]^box[(box[i]+box[j])%256]);}return out;}
  function b64(data,table){var out='',i,j;for(i=0;i<data.length;i+=3){var n=(data[i]<<16)|((data[i+1]||0)<<8)|(data[i+2]||0),count=Math.min(3,data.length-i)+1;for(j=0;j<count;j++)out+=table[(n>>>(18-6*j))&63];}while(out.length%4)out+='=';return out;}
  function pair(a,r,low,high){var n=Math.floor(r()*65535);if(low===undefined)low=n&255;if(high===undefined)high=(n>>8)&255;return [(low&170)|(a[0]&85),(low&85)|(a[0]&170),(high&170)|(a[1]&85),(high&85)|(a[1]&170)];}
  function expand(a,r){var out=[],i,n;for(i=0;i<a.length;i+=3){if(i+2>=a.length){out.push(a[i]);if(i+1<a.length&&a[i+1])out.push(a[i+1]);continue;}n=Math.floor(r()*1000)&255;out.push((n&145)|(a[i]&110),(n&66)|(a[i+1]&189),(n&44)|(a[i+2]&211),(a[i]&145)|(a[i+1]&66)|(a[i+2]&44));}return out;}
  function generate(query,body,ua,now,random) {
    var r=random||Math.random,f={},i,j,info='1920|947|1920|1032|1920|1032|1920|1080|Win32',tail=String((now+3)%256)+',';
    if(now<1721836800000)throw new Error('Invalid system clock');
    f[24]=41;f[26]=Math.floor((now-1721836800000)/1209600000);f[27]=6;f[28]=3;f[35]=1;f[36]=0;f[38]=33;f[39]=0;f[66]=3;f[79]=bytes(info).length;f[80]=0;f[84]=bytes(tail).length;f[85]=0;
    function le(start,value,count){for(var k=0;k<count;k++)f[start+k]=Math.floor(value/Math.pow(256,k))&255;}
    le(29,now,6);le(44,14,4);le(40,0,4);le(60,now-1,6);le(67,6241,4);le(71,6383,4);
    var dg=[sm3(sm3(query+'dhzx')),sm3(sm3(body+'dhzx')),sm3(b64(rc4([0,1,14],bytes(ua.replace(/^\s+|\s+$/g,''))),s3))];
    var slots=[[48,49,51],[52,53,55],[56,57,59]],idx=[[9,18,3,11,12],[10,19,4,8,9],[11,21,5,12,13]];
    for(i=0;i<3;i++){f[slots[i][0]]=dg[i][idx[i][0]];f[slots[i][1]]=dg[i][idx[i][1]];var c=idx[i][4];for(j=idx[i][2];j<32;j++){if(dg[i][j]!==idx[i][3]){c=dg[i][j];break;}}f[slots[i][2]]=c;}
    var v=pair([1,0],r),probe=Math.floor(r()*240);if(probe>109)probe+=probe%2+1;var trip=(Math.floor(r()*255)&77)|178;v=v.concat(pair([1,0],r,probe,trip));
    var checksum=0,a=[];for(i=0;i<v.length;i++)checksum^=v[i];for(i=0;i<order.length;i++){checksum^=f[order[i]];a.push(f[order[i]]);}a=a.concat(bytes(info),bytes(tail),[checksum]);
    var lower=ua.toLowerCase(),base=lower.indexOf('edg')>=0?125:lower.indexOf('huawei')>=0?170:lower.indexOf('firefox')>=0?40:lower.indexOf('chrome')>=0?0:lower.indexOf('safari')>=0?81:210;
    var header=pair([3,82],r,undefined,(base+Math.floor(r()*40))&255);
    return b64(header.concat(rc4([211],v.concat(expand(a,r)))),s4);
  }
  return {sign:generate,sm3:sm3};
}());
