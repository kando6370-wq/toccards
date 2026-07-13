# brainstorming App 国际化强制规则设计

## 背景

当前 `superpowers:brainstorming` 会在实现前要求先理解项目、澄清需求、提出方案并沉淀设计，但没有对移动 App 的国际化做显式约束。后续如果用户提出 iOS 或 Android App 相关需求，agent 可能默认按单语言设计，导致架构、文案、测试和验收标准遗漏多语言能力。

本设计补充一条最小强制规则：凡是需求涉及 iOS 或 Android App，brainstorming 阶段必须把国际化、多语言版本作为默认要求纳入设计。

## 范围

包含：

- 修改本地插件缓存中的 `superpowers:brainstorming/SKILL.md`。
- 在 “Understanding the idea” 相关规则中新增一条移动 App 国际化约束。
- 明确 iOS 与 Android App 都适用。
- 明确未被用户覆盖时，默认语言为英语，首批支持语言为日语，其他语言后续扩展。
- 明确语言清单需要扩展时，需要澄清新增语言和 fallback 策略。

不包含：

- 修改 frontmatter description。
- 修改流程图。
- 修改其他 superpowers skill。
- 为某个具体 App 实现国际化代码。
- 建立新的项目级 AGENTS 规则。

## 设计决策

采用最小文档规则变更：在 `The Process` 的 `Understanding the idea` 小节中新增一条 bullet。该位置已经负责定义需求理解和澄清阶段的行为，适合放置“移动 App 默认必须多语言”的约束。

不把规则放进 checklist，因为这会把所有 brainstorming 任务都变成额外步骤；移动 App 国际化只在 iOS 或 Android App 需求触发时适用。也不修改 frontmatter description，因为 description 应只描述触发条件，放入流程细节会降低 skill 可维护性。

## 语言策略

默认策略如下：

- 默认语言：英语。
- 首批支持语言：日语。
- 其他语言：后续扩展，不在初始设计中默认纳入。
- fallback：未指定其他策略时，缺失翻译回退到英语。

这是一条本地 `superpowers:brainstorming` 默认规则。用户在具体任务中显式指定其他默认语言或目标语言时，以用户的具体要求为准。

## 拟新增规则

建议英文规则如下，保持目标 skill 的原始语言风格：

```markdown
- For any iOS or Android app, internationalization and multilingual versions are mandatory requirements by default. Treat localization as part of the design from the start. Unless the user specifies otherwise, use English as the default language, support Japanese in the initial multilingual version, defer other languages to later expansion, and use English as the fallback for missing translations.
```

## 验收标准

- `SKILL.md` 包含一条明确覆盖 iOS 和 Android App 的国际化/多语言强制规则。
- 规则表达为默认强制要求，而不是可选建议。
- 规则明确默认语言为英语、首批支持语言为日语、其他语言后续扩展。
- 规则明确未指定其他 fallback 时回退到英语。
- 不改动 checklist、流程图、frontmatter 或其他 skill。
- 文档中不留下占位标记或含糊占位。

## 验证策略

- 用文本搜索确认目标规则已写入 `SKILL.md`。
- 用文本搜索确认没有引入占位标记。
- 由于这是 skill 文档修改，实际实现阶段需要按 `writing-skills` 的要求先设计并运行至少一个压力场景，确认现有 skill 没有该约束，再写入规则并复查。

## 风险

- 目标文件位于插件缓存目录，未来插件升级可能覆盖本地修改。
- 本次只修改本地缓存，不会同步到上游插件源。
