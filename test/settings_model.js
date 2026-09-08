const assert = require('node:assert/strict')
const Model = require('../Model.js')
const remap = { keys: [
  { key: 0, label: 'Primary click', value: 80 },
  { key: '82', label: 'Middle button', value: 82 },
  { key: '999', label: 'New device control', value: 999 }
] }
const divert = { keys: [
  { key: 82, label: 'Middle button', value: 0 },
  { key: '195', label: 'Gesture button', value: 1 }
] }
const controls = Model.assignmentControls(remap, divert)
assert.deepEqual(controls.map(c => c.key), ['0', '82', '999', '195'])
assert.equal(controls[1].remap, remap.keys[1])
assert.equal(controls[1].divert, divert.keys[0])
assert.equal(controls[2].label, 'New device control')
assert.equal(controls[3].remap, null)
assert.deepEqual(Model.assignmentControls(null, null), [])
assert.equal(Model.assignmentControls(null, { keys: [{}, null, { key: '__proto__' }] }).length, 1)
const extras = [
  { name: 'pointer_speed', kind: 'range' },
  { name: 'report_rate', kind: 'choice' },
  { name: 'custom-remap', kind: 'map_choice' },
  { name: 'custom-lock', kind: 'multiple_toggle' }
]
assert.deepEqual(Model.remainingSettings({ settings: extras }, ['dpi']), extras)
console.log('Settings model checks passed')
