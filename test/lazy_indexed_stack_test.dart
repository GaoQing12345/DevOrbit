import 'package:dev_orbit/core/widgets/lazy_indexed_stack.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('builds a page only after it is first selected', (tester) async {
    final built = <String>{};
    final visible = <String, bool>{};
    final host = GlobalKey<_HostState>();

    await tester.pumpWidget(
      MaterialApp(
        home: _Host(
          key: host,
          pages: [
            _ProbePage(name: 'home', built: built, visible: visible),
            _ProbePage(name: 'settings', built: built, visible: visible),
            _ProbePage(name: 'tool', built: built, visible: visible),
          ],
        ),
      ),
    );

    expect(built, {'home'});
    expect(visible['home'], isTrue);

    host.currentState!.show(2);
    await tester.pump();

    expect(built, {'home', 'tool'});
    expect(visible['tool'], isTrue);
    expect(visible['home'], isFalse);

    host.currentState!.show(1);
    await tester.pump();

    expect(built, {'home', 'settings', 'tool'});
    expect(visible['settings'], isTrue);
  });

  testWidgets('keeps a visited page mounted while another is shown', (
    tester,
  ) async {
    final host = GlobalKey<_HostState>();

    await tester.pumpWidget(
      MaterialApp(
        home: _Host(
          key: host,
          pages: const [
            _CounterPage(label: 'first'),
            _CounterPage(label: 'second'),
          ],
        ),
      ),
    );

    expect(find.text('first: 0'), findsOneWidget);

    await tester.tap(find.text('first: 0'));
    await tester.pump();
    expect(find.text('first: 1'), findsOneWidget);

    host.currentState!.show(1);
    await tester.pump();
    host.currentState!.show(0);
    await tester.pump();

    expect(find.text('first: 1'), findsOneWidget);
  });
}

class _Host extends StatefulWidget {
  const _Host({super.key, required this.pages});

  final List<Widget> pages;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int _index = 0;

  void show(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    return LazyIndexedStack(index: _index, children: widget.pages);
  }
}

class _ProbePage extends StatelessWidget {
  const _ProbePage({
    required this.name,
    required this.built,
    required this.visible,
  });

  final String name;
  final Set<String> built;
  final Map<String, bool> visible;

  @override
  Widget build(BuildContext context) {
    built.add(name);
    // Pages use this signal to blur their editor while another one is shown.
    visible[name] = Visibility.of(context);
    return Text(name);
  }
}

class _CounterPage extends StatefulWidget {
  const _CounterPage({required this.label});

  final String label;

  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _count++),
      child: Text('${widget.label}: $_count'),
    );
  }
}
