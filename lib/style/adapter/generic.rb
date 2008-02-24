class Style
  # This requires config[:adapter_config][:script] || 'style_adapter',
  # which means you can use it to host other supported web frameworks.
  # Those frameworks should start the server that style is currently using,
  # in order to pick up the correct socket.
  def run
   require(config[:adapter_config][:script] || 'style_adapter')
  end
end
