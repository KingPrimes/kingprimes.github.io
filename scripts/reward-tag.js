/**
 * Hexo Tag Plugin for Reward Page
 * 在 Markdown 中使用 {% reward_stats %} 和 {% reward_table %} 标签
 */

hexo.extend.tag.register('reward_stats', function() {
  const data = hexo.locals.get('data');
  const rewardLog = data.reward_log;
  
  if (!rewardLog || !rewardLog.logs) {
    return '<div class="reward-stats-error">无法加载赞助数据</div>';
  }
  
  let total = 0;
  let maxAmount = 0;
  let maxSponsor = '';
  let wechatTotal = 0;
  let alipayTotal = 0;
  let wechatCount = 0;
  let alipayCount = 0;
  
  rewardLog.logs.forEach(log => {
    const money = parseFloat(log.money);
    total += money;
    
    if (money > maxAmount) {
      maxAmount = money;
      maxSponsor = log.sponsor || '匿名';
    }
    
    if (log.origin === '微信') {
      wechatTotal += money;
      wechatCount++;
    } else if (log.origin === '支付宝') {
      alipayTotal += money;
      alipayCount++;
    }
  });
  
  const symbol = rewardLog.symbol || '¥';
  const animation = rewardLog.animation ? 'animate' : '';
  
  return `
<div class="reward-stats-container">
  <div class="reward-stats-card">
    <div class="reward-stats-title">
      <i class="fas fa-chart-line"></i>
      <span>赞助统计</span>
    </div>
    
    <div class="reward-stats-grid">
      <div class="stats-item">
        <i class="fas fa-coins"></i>
        <div class="stats-content">
          <div class="stats-label">累计赞助</div>
          <div class="stats-value ${animation}">${symbol}${total.toFixed(2)}</div>
        </div>
      </div>
      
      <div class="stats-item">
        <i class="fas fa-trophy"></i>
        <div class="stats-content">
          <div class="stats-label">单笔最大</div>
          <div class="stats-value ${animation}">${symbol}${maxAmount.toFixed(2)}</div>
          <div class="stats-sponsor">来自 ${maxSponsor}</div>
        </div>
      </div>
      
      <div class="stats-item">
        <i class="fas fa-hands-helping"></i>
        <div class="stats-content">
          <div class="stats-label">赞助次数</div>
          <div class="stats-value ${animation}">${rewardLog.logs.length} 次</div>
        </div>
      </div>
    </div>
    
    <div class="stats-divider"></div>
    
    <div class="stats-payment-row">
      <div class="stats-payment-item">
        <div class="payment-icon">
          <i class="fab fa-weixin" style="color: #09BB07;"></i>
        </div>
        <div class="payment-name">微信</div>
        <div class="payment-amount">${symbol}${wechatTotal.toFixed(2)}</div>
        <div class="payment-count">${wechatCount} 次赞助</div>
      </div>
      
      <div class="stats-payment-item">
        <div class="payment-icon">
          <i class="fab fa-alipay" style="color: #1677FF;"></i>
        </div>
        <div class="payment-name">支付宝</div>
        <div class="payment-amount">${symbol}${alipayTotal.toFixed(2)}</div>
        <div class="payment-count">${alipayCount} 次赞助</div>
      </div>
    </div>
  </div>
</div>
  `;
});

hexo.extend.tag.register('reward_table', function(args) {
  const origin = args[0]; // '微信' 或 '支付宝'
  const data = hexo.locals.get('data');
  const rewardLog = data.reward_log;
  
  if (!rewardLog || !rewardLog.logs) {
    return '<div class="reward-table-error">无法加载赞助数据</div>';
  }
  
  const symbol = rewardLog.symbol || '¥';
  
  // 筛选并排序
  let logs = rewardLog.logs
    .filter(log => log.origin === origin);
  
  // 生成表格行
  let tableRows = logs.map(log => {
    const remark = log.remark || '-';
    // 格式化日期为 YYYY-M-D 格式
    let formattedDate;
    if (log.date instanceof Date) {
      // 如果是 Date 对象，格式化为 YYYY-M-D
      const year = log.date.getFullYear();
      const month = log.date.getMonth() + 1;
      const day = log.date.getDate();
      formattedDate = `${year}-${month}-${day}`;
    } else {
      // 如果是字符串，直接使用
      formattedDate = log.date;
    }
    return `| ${log.sponsor} | ${symbol}${log.money} | ${formattedDate} | ${remark} |`;
  }).join('\n');
  
  return `
| 名字 | 金额 | 日期 | 备注 |
|------|------|------|------|
${tableRows}
  `;
});
