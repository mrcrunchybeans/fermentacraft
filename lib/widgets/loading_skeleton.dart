// lib/widgets/loading_skeleton.dart
// Copyright 2024 Brian Henson
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// Animated skeleton loader for better perceived performance
class SkeletonLoader extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;
  final Color? baseColor;
  final Color? highlightColor;

  const SkeletonLoader({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
    this.baseColor,
    this.highlightColor,
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor = widget.baseColor ?? colorScheme.surfaceContainerHigh;
    final highlightColor =
        widget.highlightColor ?? colorScheme.surfaceContainerHighest;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [
                (_controller.value - 0.3).clamp(0.0, 1.0),
                _controller.value.clamp(0.0, 1.0),
                (_controller.value + 0.3).clamp(0.0, 1.0),
              ],
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Loading skeleton for a card with title and content
class SkeletonCard extends StatelessWidget {
  final int lines;
  final double spacing;

  const SkeletonCard({
    super.key,
    this.lines = 3,
    this.spacing = 8,
  });

  @override
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            const SkeletonLoader(
              width: 150,
              height: 20,
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
            SizedBox(height: spacing * 2),
            // Content lines
            ...List.generate(
              lines,
              (index) => Padding(
                padding: EdgeInsets.only(bottom: spacing),
                child: SkeletonLoader(
                  width: index == lines - 1 ? 200 : double.infinity,
                  height: 16,
                  borderRadius: const BorderRadius.all(Radius.circular(4)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loading state overlay for replacing content while fetching
class LoadingState extends StatelessWidget {
  final String? message;
  final Widget? child;
  final bool isLoading;

  const LoadingState({
    super.key,
    this.message,
    this.child,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!isLoading && child != null) {
      return child!;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// Wrapper for async operations with automatic loading/error/success states
class AsyncBuilder<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(BuildContext, T) builder;
  final Widget Function(BuildContext, Object)? onError;
  final String? loadingMessage;

  const AsyncBuilder({
    super.key,
    required this.future,
    required this.builder,
    this.onError,
    this.loadingMessage,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          if (onError != null) {
            return onError!(context, snapshot.error!);
          }
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Error loading data',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData) {
          return LoadingState(message: loadingMessage);
        }

        return builder(context, snapshot.data as T);
      },
    );
  }
}
