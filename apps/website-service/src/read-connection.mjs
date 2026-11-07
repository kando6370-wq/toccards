import postgres from 'postgres';
import { createPostgresStore } from './postgres-store.mjs';

/** @template T @param {string} connectionString @param {(store: ReturnType<typeof createPostgresStore>) => Promise<T>} operation */
export async function withReadOnlyCatalog(connectionString, operation) {
 if (!connectionString || !/^postgres(?:ql)?:\/\//.test(connectionString)) throw new Error('A dedicated read-only catalog connection is required.');
 const client=postgres(connectionString,{max:2,fetch_types:false,connect_timeout:3,idle_timeout:5,prepare:true});
 try {
  return await client.begin('ISOLATION LEVEL REPEATABLE READ READ ONLY',async transaction=>{
   await transaction.unsafe("SET LOCAL statement_timeout = '1500ms'",[],{prepare:true});
   await transaction.unsafe("SET LOCAL lock_timeout = '750ms'",[],{prepare:true});
   const [state]=await transaction.unsafe("SELECT current_setting('transaction_read_only') AS read_only",[],{prepare:true});
   if(state?.read_only!=='on')throw new Error('Read-only transaction was not enforced.');
   const deadline=Date.now()+4500;
   return operation(createPostgresStore(async(sql,values)=>{if(Date.now()>deadline)throw new Error('Catalog read budget exhausted.');return Array.from(await transaction.unsafe(sql,values,{prepare:true}));}));
  });
 } finally { await client.end({timeout:2}); }
}
