const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '..', 'app.js'), 'utf8')
  .replace(/^\$\('#today-chip'\).*$/m, '') +
  '\nglobalThis.subject={db, sum, balance, monthTx, spentCategory, safeDaily};';

function createApp(data = {}) {
  const context = vm.createContext({
    localStorage: { getItem: () => JSON.stringify(data) },
    Date, Intl, structuredClone, console, window: { PAISA_CLOUD: {} }
  });
  vm.runInContext(source, context);
  return context.subject;
}

test('income and expenses change tracked balance in the right direction', () => {
  const app = createApp({ openingBalance: 2000, transactions: [
    { type: 'income', amount: 500 }, { type: 'expense', amount: 125.5 }
  ] });
  assert.equal(app.balance(), 2374.5);
});

test('period and category totals only include this month expenses', () => {
  const now = new Date();
  const month = `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}-02`;
  const prior = `${now.getFullYear()}-${String(now.getMonth()).padStart(2,'0')}-02`;
  const app = createApp({ transactions: [
    { date: month, type: 'expense', category: 'Chai', amount: 35 },
    { date: month, type: 'income', category: 'Chai', amount: 1000 },
    { date: prior, type: 'expense', category: 'Chai', amount: 50 }
  ] });
  assert.equal(app.monthTx().length, 2);
  assert.equal(app.spentCategory('Chai'), 35);
});

test('edits and deletions are reflected by recalculating from the ledger', () => {
  const app = createApp({ openingBalance: 1000, transactions: [
    { type: 'expense', amount: 100 }, { type: 'expense', amount: 50 }
  ] });
  app.db.transactions[0].amount = 175;
  assert.equal(app.balance(), 775);
  app.db.transactions.pop();
  assert.equal(app.balance(), 825);
});

test('daily guide is finite and never negative with an exhausted budget', () => {
  const app = createApp({ monthlyIncome: 1000, budgets: { 'Food & snacks': 1200 }, transactions: [] });
  assert.equal(app.safeDaily(), 0);
  assert.ok(Number.isFinite(app.safeDaily()));
});
