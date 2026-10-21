import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:localization/localization.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:ui/keys.dart';
import 'package:ui/src/common/extensions/app_exception_x.dart';
import 'package:ui/src/common/widgets/error_view.dart';
import 'package:ui/src/di.dart';
import 'package:ui/src/foo/blocs/load_foo_bloc.dart';

/// The one screen: wires the example bloc. Replace the body with the app's
/// first feature (writing-load-blocs → Page wiring).
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => inject<LoadFooBloc>()..reload(),
    child: const _HomeView(),
  );
}

class _HomeView extends StatelessWidget {
  const _HomeView();

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<LoadFooBloc>();
    return BlocListener<LoadFooBloc, LoadFooBlocState>(
      listenWhen: (_, current) => current is LoadFooBlocStateReloadError,
      listener: (context, state) {
        if (state is! LoadFooBlocStateReloadError) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.error.message(context.strings))),
        );
      },
      child: Scaffold(
        key: keys.home.page,
        appBar: AppBar(title: Text(context.strings.appTitle)),
        body: RefreshIndicator(
          onRefresh: bloc.reload,
          child: BlocBuilder<LoadFooBloc, LoadFooBlocState>(
            builder: (context, state) => switch (state) {
              LoadFooBlocStateLoaded(:final foo) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  ListTile(key: keys.home.foo(foo.id), title: Text(foo.id)),
                ],
              ),
              LoadFooBlocStateError(:final error) => ErrorView(
                error: error,
                onRetry: bloc.reload,
              ),
              // A skeleton of the real row, never a full-screen spinner
              // (ui rule → Widgets).
              LoadFooBlocStateIdle() ||
              LoadFooBlocStateLoading() => Skeletonizer(
                key: keys.home.skeleton,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [ListTile(title: Text(BoneMock.title))],
                ),
              ),
            },
          ),
        ),
      ),
    );
  }
}
