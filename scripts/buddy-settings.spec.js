const { test, expect } = require('@playwright/test');
const path = require('path');
const fs = require('fs');

async function open(page) {
  await page.goto('file://' + path.resolve(__dirname, '../dist/index.html'));
  await page.waitForFunction(() => window.__buddy && window.__buddy.state.today.date);
}

test('ordinary backticks are text, not drawer shortcuts', async ({ page }) => {
  await open(page);
  const result = await page.evaluate(() => {
    document.querySelector('#morning').classList.add('hidden');
    const drawer = document.querySelector('#drawer');
    drawer.classList.remove('translate-x-full');
    const input = document.createElement('input');
    document.body.append(input); input.focus();
    const event = new KeyboardEvent('keydown', { key: '`', code: 'Backquote', bubbles: true, cancelable: true });
    input.dispatchEvent(event);
    return { prevented: event.defaultPrevented, closed: drawer.classList.contains('translate-x-full') };
  });
  expect(result).toEqual({ prevented: false, closed: false });
});

test('native shell never registers an unmodified typing key', () => {
  const rust = fs.readFileSync(path.resolve(__dirname, '../src-tauri/src/lib.rs'), 'utf8');
  expect(rust).not.toContain('.register("Backquote")');
});

test('morning opt-out persists locally without completing the shared day', async ({ page }) => {
  await open(page);
  await page.evaluate(async () => {
    await window.__buddy.setLocalPreference('autoMorning', false);
    document.querySelector('#morning').classList.add('hidden');
    window.__buddy.state.today.morningDone = false;
    await window.__buddy.maybeShowMorning('test');
  });
  await expect(page.locator('#morning')).toHaveClass(/hidden/);
  expect(await page.evaluate(() => window.__buddy.state.today.morningDone)).toBe(false);
  await page.reload();
  await page.waitForFunction(() => window.__buddy && window.__buddy.localPreferencesReady());
  await expect(page.locator('#morning')).toHaveClass(/hidden/);
  await page.evaluate(() => window.__buddy.showMorning());
  await expect(page.locator('#morning')).not.toHaveClass(/hidden/);
});

for (const limit of [3, 4, 5, 6]) {
  test(`limit ${limit}: warning, capacity and Boss threshold agree`, async ({ page }) => {
    await open(page);
    const result = await page.evaluate(L => {
      const b = window.__buddy; b.suppressSave();
      b.state.extras.taskLimit = { value: L, v: 1, writer: 'test' };
      return Array.from({length: 9}, (_, n) => {
        b.state.items = Array.from({length:n}, (_, i) => ({ id:'task'+i, text:'Task '+i, state:'neutral', v:1 }));
        return {level:b.warnLevel(), free:b.freeSlots(), boss:b.bossThreshold()};
      });
    }, limit);
    expect(result).toEqual(Array.from({length:9}, (_,n)=>({level:n>=limit?2:n===limit-1?1:0,free:Math.max(0,limit-n),boss:limit-1})));
  });
}

test('limit-only sync survives an unrelated newer legacy save and parks overflow', async ({ page }) => {
  await open(page);
  const r = await page.evaluate(() => {
    const b=window.__buddy;
    const old={version:1,savedAt:2000,today:{date:b.localDate(),morningDone:true,items:Array.from({length:6},(_,i)=>({id:'x'+i,text:'Task '+i,state:'neutral',v:1}))},history:[],deferred:[],settings:{celebrate:100,reserveSpace:false},tombstones:{}};
    const chosen={...old,savedAt:1000,taskLimit:{value:3,v:2,writer:'mac'}};
    const forward=window.mergeWire(chosen,old), reverse=window.mergeWire(old,chosen);
    return {limit:forward.taskLimit,active:forward.today.items.length,future:forward.deferred.length,symmetric:JSON.stringify(forward)===JSON.stringify(reverse),changed:b.blobContentKey(chosen)!==b.blobContentKey(old)};
  });
  expect(r).toEqual({limit:{value:3,v:2,writer:'mac'},active:3,future:3,symmetric:true,changed:true});
});

for (const previousDay of [false, true]) for (const done of [false, true]) {
  test(`parked task keeps offline ${done?'completion':'edit'}, older day ${previousDay}`, async ({ page }) => {
    await open(page);
    const r=await page.evaluate(({previousDay,done})=>{
      const base={version:1,savedAt:2000,today:{date:'2026-09-16',morningDone:true,items:[]},history:[],deferred:[],settings:{celebrate:100,reserveSpace:false},tombstones:{}};
      const a={...base,taskLimit:{value:3,v:2,writer:'mac'},deferred:[{id:'x',text:'Old title',v:1,wake:''}]};
      const b={...base,savedAt:1000,today:{...base.today,date:previousDay?'2026-09-15':'2026-09-16',items:[{id:'x',text:'Updated title',state:done?'done':'neutral',doneAt:done?1000:null,v:2}]}};
      const m=window.mergeWire(a,b), key=window.__buddy.blobContentKey;
      return {future:m.deferred.map(d=>({text:d.text,v:d.v})),completed:m.history.some(h=>h.items.some(i=>i.id==='x'&&i.done&&i.text==='Updated title')), symmetric:key(m)===key(window.mergeWire(b,a)),stable:key(m)===key(window.mergeWire(m,b))&&key(m)===key(window.mergeWire(m,a))};
    },{previousDay,done});
    expect(r).toEqual({future:done?[]:[{text:'Updated title',v:2}],completed:done,symmetric:true,stable:true});
  });
}

test('reducing requires confirmation, preserves focused work and survives a stale peer', async ({ page }) => {
  await open(page);
  await page.evaluate(()=>{
    const b=window.__buddy; b.suppressSave(); b.state.pinned=true;
    b.state.items=Array.from({length:6},(_,i)=>({id:'x'+i,text:'Task '+i,state:i===5?'focused':'neutral',v:1}));
    document.querySelector('#morning').classList.add('hidden');
    b.openDrawer();b.openSettings();
  });
  await page.getByRole('button',{name:'3 active tasks',exact:true}).click();
  await expect(page.locator('#taskLimitConfirm')).toBeVisible();
  expect(await page.evaluate(()=>window.__buddy.activeCount())).toBe(6);
  await page.getByRole('button',{name:'Cancel',exact:true}).click();
  expect(await page.evaluate(()=>window.__buddy.taskLimit())).toBe(6);
  await page.getByRole('button',{name:'3 active tasks',exact:true}).click();
  await page.getByRole('button',{name:'Move to Future',exact:true}).click();
  const r=await page.evaluate(()=>({limit:window.__buddy.taskLimit(),ids:window.__buddy.state.items.map(i=>i.id),future:window.__buddy.state.deferred.length}));
  expect(r).toEqual({limit:3,ids:['x0','x1','x5'],future:3});
});

test('malformed browser preferences can be repaired by an explicit switch change', async ({ page }) => {
  await open(page);
  await page.evaluate(()=>localStorage.setItem('buddy.preferences.v1','not json'));
  await page.reload();
  await page.waitForFunction(()=>window.__buddy?.localPreferencesReady());
  expect(await page.evaluate(()=>window.__buddy.setLocalPreference('autoMorning',false))).toBe(true);
  expect(await page.evaluate(()=>JSON.parse(localStorage.getItem('buddy.preferences.v1')).autoMorning)).toBe(false);
});

test('morning opt-out survives rollover and resume without dropping carry-over', async ({ page }) => {
  await open(page);
  const result=await page.evaluate(async()=>{
    const b=window.__buddy;b.suppressSave();await b.setLocalPreference('autoMorning',false);
    b.state.extras.taskLimit={value:3,v:1,writer:'test'};
    b.state.today.date='2020-01-01';b.state.today.morningDone=true;
    b.state.items=Array.from({length:6},(_,i)=>({id:'carry'+i,text:'Carry '+i,state:'neutral',v:1}));
    b.state.deferred=[];document.querySelector('#morning').classList.add('hidden');
    liveRolloverCheck();await resumeMorningCheckInner();
    return {active:b.activeCount(),future:b.state.deferred.length,date:b.state.today.date,morningDone:b.state.today.morningDone,hidden:document.querySelector('#morning').classList.contains('hidden'),today:b.localDate()};
  });
  expect(result).toEqual({active:3,future:3,date:result.today,morningDone:false,hidden:true,today:result.today});
});

test('optional browser shortcut ignores editable, composing and repeated keys', async ({ page }) => {
  await open(page);
  const result=await page.evaluate(async()=>{
    const b=window.__buddy;await b.setLocalPreference('shortcutEnabled',true);
    document.querySelector('#morning').classList.add('hidden');b.openDrawer();
    const input=document.createElement('input');document.body.append(input);input.focus();
    const send=(target,extra={})=>{const e=new KeyboardEvent('keydown',{key:'b',code:'KeyB',metaKey:true,altKey:true,bubbles:true,cancelable:true,...extra});target.dispatchEvent(e);return e.defaultPrevented;};
    const edited=send(input);input.blur();const repeated=send(document,{repeat:true}),composed=send(document,{isComposing:true});
    return {edited,repeated,composed,closed:document.querySelector('#drawer').classList.contains('translate-x-full')};
  });
  expect(result).toEqual({edited:false,repeated:false,composed:false,closed:false});
});
