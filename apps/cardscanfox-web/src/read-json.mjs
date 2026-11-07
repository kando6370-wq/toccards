export async function readBoundedJson(response,limit=524288){
 const declared=Number(response.headers.get('content-length'));if(declared>limit)throw new Error('Catalog response is too large.');
 if(!response.body)throw new Error('Catalog response has no body.');const reader=response.body.getReader(),chunks=[];let size=0;
 try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>limit){await reader.cancel();throw new Error('Catalog response is too large.');}chunks.push(value);}}
 finally{reader.releaseLock();}
 const body=new Uint8Array(size);let offset=0;for(const chunk of chunks){body.set(chunk,offset);offset+=chunk.length;}return JSON.parse(new TextDecoder().decode(body));
}
