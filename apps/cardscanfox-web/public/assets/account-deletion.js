const SUPPORT_EMAIL = 'support@tcgcard.fun';
const PLATFORM_LABELS = {android:'Android',ios:'iOS'};

function hasControlCharacters(value) {
  return /[\u0000-\u001f\u007f]/u.test(value);
}

export function normalizeDeletionPlatform(value) {
  if(typeof value!=='string'||hasControlCharacters(value))return null;
  const normalized=value.trim().toLowerCase();
  return normalized==='android'||normalized==='ios'?normalized:null;
}

export function normalizeDeletionEmail(value) {
  if(typeof value!=='string'||hasControlCharacters(value))return null;
  const email=value.trim();
  if(!email||email.length>254||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/u.test(email))return null;
  return email;
}

export function buildDeletionRequest(platformValue,emailValue) {
  const platform=normalizeDeletionPlatform(platformValue);
  const email=normalizeDeletionEmail(emailValue);
  if(!platform)throw new TypeError('Select Android or iOS.');
  if(!email)throw new TypeError('Enter a valid account email.');
  const label=PLATFORM_LABELS[platform];
  const other=platform==='android'?'iOS':'Android';
  const subject=`Card AI account deletion request — ${label}`;
  const body=[
    `I request deletion of my Card AI ${label} account and its associated data.`,
    '',
    `Platform: ${label}`,
    `Card AI account email: ${email}`,
    '',
    'I understand that this request applies to the selected platform only.',
    `My ${other} account and its data are not part of this request.`,
    'Please verify my identity before processing the request and confirm the next steps.',
  ].join('\n');
  return {
    platform,
    label,
    email,
    subject,
    body,
    plainText:`To: ${SUPPORT_EMAIL}\nSubject: ${subject}\n\n${body}`,
    mailto:`mailto:${SUPPORT_EMAIL}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`,
  };
}

function required(root,selector) {
  const element=root.querySelector(selector);
  if(!element)throw new Error(`Account deletion page is missing ${selector}`);
  return element;
}

export function initAccountDeletion(root,dependencies={}) {
  if(!root)return null;
  const platformInputs=[...root.querySelectorAll('input[data-deletion-platform]')];
  const email=required(root,'[data-deletion-email]');
  const openButton=required(root,'[data-open-deletion-email]');
  const copyButton=required(root,'[data-copy-deletion-request]');
  const platformError=required(root,'[data-deletion-platform-error]');
  const emailError=required(root,'[data-deletion-email-error]');
  const scopeTitle=required(root,'[data-deletion-scope-title]');
  const scopeNotice=required(root,'[data-deletion-scope-notice]');
  const iosSubscription=required(root,'[data-ios-subscription]');
  const details=required(root,'[data-deletion-details]');
  const detailsTitle=required(root,'[data-deletion-details-title]');
  const template=required(root,'[data-deletion-template]');
  const status=required(root,'[data-deletion-status]');
  if(platformInputs.length!==2)throw new Error('Account deletion page requires Android and iOS choices.');

  let revision=0;
  const selectedPlatform=()=>platformInputs.find(input=>input.checked)?.value??'';
  const setInvalid=(control,error,invalid)=>{
    control.setAttribute('aria-invalid',String(invalid));
    error.hidden=!invalid;
  };
  const clearPreparedState=()=>{
    revision+=1;
    details.hidden=true;
    detailsTitle.textContent='Request details';
    template.value='';
    status.textContent='';
  };
  const updateScope=()=>{
    const platform=normalizeDeletionPlatform(selectedPlatform());
    iosSubscription.hidden=platform!=='ios';
    if(platform==='android'){
      scopeTitle.textContent='Your Android platform account and data';
      scopeNotice.textContent='Your iOS account and its business data remain available.';
    }else if(platform==='ios'){
      scopeTitle.textContent='Your iOS platform account and data';
      scopeNotice.textContent='Your Android account and its business data remain available.';
    }else{
      scopeTitle.textContent='Select a platform to see the scope';
      scopeNotice.textContent='Selecting one platform does not delete the other platform account.';
    }
  };
  const validate=()=>{
    const platform=normalizeDeletionPlatform(selectedPlatform());
    const normalizedEmail=normalizeDeletionEmail(email.value);
    setInvalid(platformInputs[0].closest?.('fieldset')??platformInputs[0],platformError,!platform);
    setInvalid(email,emailError,!normalizedEmail);
    return platform&&normalizedEmail?{platform,email:normalizedEmail}:null;
  };
  const prepare=()=>{
    const input=validate();
    if(!input)return null;
    const request=buildDeletionRequest(input.platform,input.email);
    revision+=1;
    details.hidden=false;
    template.value=request.plainText;
    return {request,revision};
  };
  const currentMatches=request=>normalizeDeletionPlatform(selectedPlatform())===request.platform&&normalizeDeletionEmail(email.value)===request.email;
  const openMailto=dependencies.openMailto??(href=>globalThis.location?.assign(href));
  const clipboard=Object.prototype.hasOwnProperty.call(dependencies,'clipboard')?dependencies.clipboard:globalThis.navigator?.clipboard;
  const openDraft=()=>{
    const prepared=prepare();
    if(!prepared)return;
    detailsTitle.textContent='Email draft prepared';
    status.textContent='Continue in your email app. Your deletion request has not been received until you send the email.';
    try{
      openMailto(prepared.request.mailto);
    }catch{
      status.textContent=`Your email app could not be opened. Copy the request details below and send them to ${SUPPORT_EMAIL}. Nothing has been sent.`;
    }
  };
  const copyRequest=async()=>{
    const prepared=prepare();
    if(!prepared)return;
    detailsTitle.textContent='Request details';
    status.textContent='Request details ready. Nothing has been sent.';
    if(!clipboard||typeof clipboard.writeText!=='function'){
      template.select?.();
      status.textContent='Copy is unavailable in this browser. Select the request details and copy them manually. Nothing has been sent.';
      return;
    }
    try{
      await clipboard.writeText(prepared.request.plainText);
      if(prepared.revision!==revision||!currentMatches(prepared.request))return;
      status.textContent='Request details copied. Nothing has been sent. Paste them into an email to support@tcgcard.fun.';
    }catch{
      if(prepared.revision!==revision||!currentMatches(prepared.request))return;
      template.select?.();
      status.textContent='Copy was unavailable. Select the request details and copy them manually. Nothing has been sent.';
    }
  };

  for(const input of platformInputs){
    input.addEventListener('change',()=>{
      setInvalid(input.closest?.('fieldset')??platformInputs[0],platformError,false);
      clearPreparedState();
      updateScope();
    });
  }
  email.addEventListener('input',()=>{
    setInvalid(email,emailError,false);
    clearPreparedState();
  });
  email.addEventListener('keydown',event=>{
    if(event.key==='Enter'){
      event.preventDefault();
      openDraft();
    }
  });
  openButton.addEventListener('click',openDraft);
  copyButton.addEventListener('click',()=>{void copyRequest();});
  openButton.disabled=false;
  copyButton.disabled=false;
  updateScope();
  return {openDraft,copyRequest};
}

if(typeof document!=='undefined'){
  const root=document.querySelector('[data-account-deletion]');
  if(root)initAccountDeletion(root);
}
