import 'package:flutter/material.dart';

typedef NavItem = ({IconData icon, IconData selectedIcon, String label});

/// Bottom bar used when there are more tabs than fit: the first [visibleCount]
/// are full width like the normal bar, the rest are reached by scrolling
/// sideways. A small arrow shows there is more (tap it to jump there).
class ScrollableNavBar extends StatefulWidget {
  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final int visibleCount;

  const ScrollableNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.visibleCount = 7,
  });

  @override
  State<ScrollableNavBar> createState() => _ScrollableNavBarState();
}

class _ScrollableNavBarState extends State<ScrollableNavBar> with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  // Gentle side-to-side nudge so the arrows are noticed.
  late final AnimationController _nudge = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
    ..repeat(reverse: true);
  bool _atStart = true;
  bool _atEnd = false;
  double _itemWidth = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateArrows();
      _showSelected(animate: false);
    });
  }

  @override
  void didUpdateWidget(ScrollableNavBar old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showSelected());
    }
  }

  @override
  void dispose() {
    _nudge.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _updateArrows() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final atStart = p.pixels <= 1;
    final atEnd = p.pixels >= p.maxScrollExtent - 1;
    if (atStart != _atStart || atEnd != _atEnd) {
      setState(() {
        _atStart = atStart;
        _atEnd = atEnd;
      });
    }
  }

  /// Scrolls just enough to bring the selected tab into view.
  void _showSelected({bool animate = true}) {
    if (!_scroll.hasClients || _itemWidth == 0) return;
    final p = _scroll.position;
    final left = widget.selectedIndex * _itemWidth;
    final right = left + _itemWidth;
    double? target;
    if (left < p.pixels) target = left;
    if (right > p.pixels + p.viewportDimension) target = right - p.viewportDimension;
    if (target == null) return;
    target = target.clamp(0, p.maxScrollExtent).toDouble();
    animate
        ? _scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
        : _scroll.jumpTo(target);
  }

  void _jump(bool toEnd) {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      toEnd ? _scroll.position.maxScrollExtent : 0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = theme.navigationBarTheme.backgroundColor ?? scheme.surfaceContainer;

    Widget arrow(bool right) => Positioned(
          top: 0,
          bottom: 0,
          right: right ? 0 : null,
          left: right ? null : 0,
          child: GestureDetector(
            onTap: () => _jump(right),
            child: Container(
              width: 26,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: right ? Alignment.centerLeft : Alignment.centerRight,
                  end: right ? Alignment.centerRight : Alignment.centerLeft,
                  colors: [background.withValues(alpha: 0), background],
                ),
              ),
              alignment: Alignment.center,
              child: AnimatedBuilder(
                animation: _nudge,
                builder: (context, child) => Transform.translate(
                  offset: Offset((right ? 1 : -1) * 4 * Curves.easeInOut.transform(_nudge.value), 0),
                  child: child,
                ),
                child: Icon(right ? Icons.chevron_right : Icons.chevron_left, size: 24, color: Colors.red),
              ),
            ),
          ),
        );

    return Material(
      color: background,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 80,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _itemWidth = constraints.maxWidth / widget.visibleCount;
              return Stack(
                children: [
                  ListView.builder(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.items.length,
                    itemExtent: _itemWidth,
                    itemBuilder: (context, i) {
                      final item = widget.items[i];
                      final selected = i == widget.selectedIndex;
                      return InkResponse(
                        onTap: () => widget.onSelected(i),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 52,
                              height: 32,
                              decoration: BoxDecoration(
                                color: selected ? scheme.secondaryContainer : Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                selected ? item.selectedIcon : item.icon,
                                color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  if (!_atStart) arrow(false),
                  if (!_atEnd) arrow(true),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
