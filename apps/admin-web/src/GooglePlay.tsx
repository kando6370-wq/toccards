import { Alert, Button, Card, DatePicker, Drawer, Input, Modal, Segmented, Select, Space, Table, Tag, Typography, message } from "antd";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { createRequestId } from "./request-id";
import { subscriptionErrorMessage, type SubscriptionRequest } from "./subscription-config/model";

type Row = Record<string, string | number | null>;
type Plan = {product_id:string; base_plan_id:string; offer_id:string};
type Approved = Plan & {revenue_event:string; revision:number};
type Config = {title:string; plans:Array<Plan & {label:string; is_default:boolean}>};
type Saved = {placement:string;draft:Config;published:Config|null;revision:number};
const productKey=(p:Plan)=>[p.product_id,p.base_plan_id,p.offer_id].join('/');
const usd=(v:unknown)=>v == null ? '—' : new Intl.NumberFormat('zh-CN',{style:'currency',currency:'USD'}).format(Number(v)/1e6);
const labels:Record<string,string>={owner_id:'Android UID',order_id:'Google 订单号',country:'国家/地区',base_plan_id:'基础方案',store_kind:'购买类型',kind:'事件',state:'状态',currency:'币种',event_at:'事件时间（UTC）',usd_micros:'金额（USD）',message_id:'消息 ID',received_at:'接收时间（UTC）',next_check_at:'下次处理',attempts:'尝试次数',last_error:'最近错误',acknowledgement:'商店确认',chain:'购买链',product_id:'商品',tax_micros:'税额（micros）',amount_micros:'原币金额（micros）',fx_snapshot:'汇率快照',topic:'消息来源',related_message_id:'关联消息 ID',checked_at:'最近回查'};
const planText=(p:Plan)=>[p.product_id,p.base_plan_id,p.offer_id || '基础价'].join(' / ');

export function PlayOrders({request,download,superAdmin,accountKey}:{request:SubscriptionRequest;download:(path:string)=>Promise<void>;superAdmin:boolean;accountKey:string}) {
  const [draft,setDraft]=useState<Record<string,string>>({}),[filters,setFilters]=useState<Record<string,string>>({}),[page,setPage]=useState(1),[detail,setDetail]=useState<Row|null>(null),[reason,setReason]=useState('');
  const params=new URLSearchParams(Object.entries(filters).filter(([,v])=>v));
  params.set('page',String(page));
  const path=`/google-play/orders?${params}`;
  const query=useQuery({queryKey:['play-report',accountKey,path],queryFn:()=>request<{scope:string;as_of?:string;rows:Row[];summary?:Record<string,number|null>}>(path)});
  const {data}=query;
  const columns=['order_id','owner_id','country','base_plan_id','kind','currency','usd_micros','state','event_at'].map(k=>({title:labels[k],dataIndex:k,key:k,render:(v:unknown)=> k==='usd_micros' ? usd(v) : String(v??'—')}));
  return <Space direction="vertical" style={{width:'100%'}}>
    {data && <Space><Tag>{data.scope}</Tag><Tag>{(filters.store_kind??'live')==='live'?'正式购买':'测试购买'}</Tag>{data.as_of && <Typography.Text type="secondary">截至 {data.as_of}</Typography.Text>}</Space>}
    <Space wrap>{['owner_id','order_id','country','base_plan_id','state'].map(k=><Input key={k} aria-label={labels[k]} placeholder={labels[k]} style={{width:150}} value={draft[k]??''} onChange={e=>setDraft({...draft,[k]:e.target.value})}/>)}
      <Select aria-label="购买类型" value={draft.store_kind??'live'} options={[{value:'live',label:'正式购买'},{value:'test',label:'测试购买'}]} onChange={v=>setDraft({...draft,store_kind:v})}/>
      <Select aria-label="资金事件" allowClear placeholder="扣款 / 退款" value={draft.kind||undefined} options={[{value:'charge',label:'扣款'},{value:'refund',label:'退款'}]} onChange={v=>setDraft({...draft,kind:v??''})}/>
      <DatePicker.RangePicker onChange={(_,range)=>setDraft({...draft,from:range[0]?`${range[0]}T00:00:00Z`:'',to:range[1]?new Date(Date.parse(`${range[1]}T00:00:00Z`)+86400000).toISOString():''})}/>
      <Button type="primary" onClick={()=>{setPage(1);setFilters({...draft});}}>查询</Button>
      <Button onClick={()=>void download(`/google-play/orders/export?${params}`).catch(e=>message.error(String(e)))}>导出 XLSX</Button>
    </Space>
    {superAdmin && <Space><Input aria-label="补账原因" placeholder="销售报告差异原因" value={reason} onChange={e=>setReason(e.target.value)}/><Button disabled={!reason.trim()||!draft.order_id} onClick={async()=>{try{await request('/google-play/orders/reconcile',{method:'POST',body:{order_id:draft.order_id,reason,request_id:createRequestId()}});await query.refetch();message.success('已回查 Play 订单');}catch(e){message.error(String(e));}}}>按报告订单号补账</Button></Space>}
    {query.error && <Alert type="error" message={query.error.message}/>}
    {data?.summary && <Space wrap>{[['订单数',data.summary.order_count],['筛选订单中的当前有效订阅',data.summary.active_chains],['毛扣款',usd(data.summary.gross_usd_micros)],['成功退款',usd(data.summary.refund_usd_micros)],['净额',usd(data.summary.net_usd_micros)],['待对账扣款',data.summary.missing_charges],['待对账退款',data.summary.missing_refunds]].map(([k,v])=><Card size="small" key={k} title={k}>{v}</Card>)}</Space>}
    <Table loading={query.isFetching} size="small" scroll={{x:'max-content'}} rowKey={(r,index)=>`${r.order_id??r.message_id}/${index}`} dataSource={data?.rows??[]} columns={[...columns,{title:'操作',key:'actions',render:(_,row:Row)=><Button type="link" onClick={()=>{setDetail(row);setReason('');}}>详情</Button>}]} pagination={{current:page,pageSize:20,total:Number(data?.summary?.total ?? data?.rows[0]?.total ?? 0),showSizeChanger:false,onChange:setPage}}/>
    <Drawer title="Google Play 订单事实" open={!!detail} onClose={()=>setDetail(null)}>{detail && Object.entries(detail).filter(([k])=>k!=='total').map(([k,v])=><p key={k}><strong>{labels[k]??k}</strong>　{typeof v==='object' && v!==null?JSON.stringify(v):String(v??'—')}</p>)}
    </Drawer>
  </Space>;
}

export function PlayConfigs({request,superAdmin,accountKey}:{request:SubscriptionRequest;superAdmin:boolean;accountKey:string}) {
  const client=useQueryClient(),[placement,setPlacement]=useState('page'),[candidate,setCandidate]=useState(''),[event,setEvent]=useState(''),[reason,setReason]=useState(''),[editing,setEditing]=useState<{value:Config;revision:number}|null>(null),[preview,setPreview]=useState(false),[busy,setBusy]=useState(false);
  const products=useQuery({queryKey:['play-products',accountKey],queryFn:()=>request<{scope:string;approved:Approved[]}>('/google-play/products')});
  const configs=useQuery({queryKey:['play-configs',accountKey],queryFn:()=>request<{scope:string;rows:Saved[]}>('/google-play/configs')});
  const store = useQuery({
    queryKey: ['play-store-catalog',accountKey], enabled: false, retry: false, gcTime: 0,
    queryFn: ({signal}) => request<{catalog:Plan[]}>('/google-play/products?refresh=1', {signal}),
  });
  const catalog = store.isSuccess ? store.data.catalog : [];
  const selectedPlan = catalog.find(plan => productKey(plan) === candidate);
  function refreshCatalog() {
    setCandidate('');
    setEvent('');
    void store.refetch();
  }
  const saved=configs.data?.rows.find(r=>r.placement===placement),approved=products.data?.approved??[];
  const draft=editing?.value ?? saved?.draft ?? {title:'Premium',plans:[]};
  function edit(value:Config){setEditing({value,revision:editing?.revision??saved?.revision??0});}
  async function write(path:string,body:Record<string,unknown>){
    if(!reason.trim()){message.warning('请填写操作原因');return;}
    setBusy(true);try{await request(`/google-play/${path}`,{method:'POST',body:{...body,request_id:createRequestId(),reason}});setEditing(null);await Promise.all([client.invalidateQueries({queryKey:['play-products',accountKey]}),client.invalidateQueries({queryKey:['play-configs',accountKey]})]);message.success('已保存');}catch(e){message.error(subscriptionErrorMessage(e));}finally{setBusy(false);}
  }
  return <Space direction="vertical" style={{width:'100%'}}>
    {products.data && <Tag>{products.data.scope}</Tag>}
    {(products.error||configs.error) && <Alert type="error" message={(products.error??configs.error)?.message}/>}
    <Input aria-label="操作原因" placeholder="操作原因" value={reason} onChange={e=>setReason(e.target.value)}/>
    <Card title="Google Play 商品目录">
      {store.isError && !store.isFetching && <Alert type="error" showIcon message={subscriptionErrorMessage(store.error)} />}
      {store.isSuccess && !store.isFetching && <Typography.Paragraph type="secondary">
        {catalog.length ? '已读取 ' + catalog.length + ' 个在售方案' : '当前应用没有可向新订阅者销售的自动续订方案。请在 Play Console 核对基础方案状态和销售地区。'}
      </Typography.Paragraph>}
      <Space wrap><Button loading={store.isFetching} onClick={refreshCatalog}>从 Play 刷新目录</Button>
    <Select disabled={store.isFetching || !catalog.length} style={{minWidth:245}} placeholder="选择在售商品 / 方案 / 优惠" value={candidate||undefined} options={catalog.map(p=>({value:productKey(p),label:planText(p)}))} onChange={v=>{setCandidate(v);setEvent(approved.find(p=>productKey(p)===v)?.revenue_event??'');}}/>
    {superAdmin && <><Input style={{width:170}} placeholder="收入事件名" value={event} onChange={e=>setEvent(e.target.value)}/><Button loading={busy} disabled={store.isFetching||!selectedPlan||!event.trim()} onClick={()=>write('products',{...selectedPlan,revenue_event:event,expected_revision:approved.find(p=>productKey(p)===candidate)?.revision??0})}>审批商品</Button></>}</Space></Card>
    <Card title="展示配置" extra={<Segmented value={placement} options={[{label:'订阅页',value:'page'},{label:'弹窗',value:'modal'}]} onChange={v=>{setPlacement(String(v));setEditing(null);}}/>}>
    <Space direction="vertical" style={{width:'100%'}}><Tag>{saved?.published?'已启用':'未启用'} · 版本 {saved?.revision??0}</Tag>
    <Input aria-label="页面标题" value={draft.title} onChange={e=>edit({...draft,title:e.target.value})}/>
    <Select mode="multiple" placeholder="按展示顺序添加已审批方案" style={{minWidth:320}} value={draft.plans.map(productKey)} options={approved.map(p=>({value:productKey(p),label:planText(p)}))} onChange={keys=>{
      const rows=keys.map((k:string)=>draft.plans.find(p=>productKey(p)===k)??{...approved.find(p=>productKey(p)===k)!,label:'',is_default:false});
      if(rows.length && !rows.some(r=>r.is_default)) rows[0]={...rows[0],is_default:true};edit({...draft,plans:rows});}}/>
    {draft.plans.map((p,i)=><Space key={productKey(p)}><Tag>{planText(p)}</Tag><Input aria-label="展示名称" placeholder="展示名称" value={p.label} onChange={e=>edit({...draft,plans:draft.plans.map((r,n)=>n===i?{...r,label:e.target.value}:r)})}/><Button onClick={()=>edit({...draft,plans:draft.plans.map((r,n)=>({...r,is_default:n===i}))})}>{p.is_default?'默认项':'设为默认'}</Button></Space>)}
    <Space><Button onClick={()=>setPreview(true)}>预览</Button><Button loading={busy} onClick={()=>write('configs',{operation:'save',placement,draft,expected_revision:editing?.revision??saved?.revision??0})}>保存草稿</Button><Button loading={busy} disabled={!saved||!!editing} onClick={()=>write('configs',{operation:'enable',placement,expected_revision:saved?.revision})}>启用</Button><Button disabled={!saved?.published} onClick={()=>write('configs',{operation:'disable',placement,expected_revision:saved?.revision})}>停用</Button></Space>
    </Space></Card><Modal title={draft.title} open={preview} onCancel={()=>setPreview(false)} footer={<Button onClick={()=>setPreview(false)}>关闭</Button>}>{draft.plans.map(p=><p key={productKey(p)}>{p.label}　{p.is_default?'默认':''}　{planText(p)}</p>)}<Typography.Text type="secondary">实际价格与优惠资格由当前用户的 Google Play 返回。</Typography.Text></Modal>
  </Space>;
}
